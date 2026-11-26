import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DButton from "discourse/ui-kit/d-button";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import { noteColourProfile } from "../lib/npn-colour-profile";
import NpnDraftAutosaver from "../lib/npn-draft-autosaver";
import { focusFieldBySelector } from "../lib/npn-focus-field";
import { saveEdit, startEditing } from "../lib/npn-form-edit";
import NpnAskIdeas from "./npn-ask-ideas";
import NpnAutosaveStatus from "./npn-autosave-status";
import NpnEditIntro from "./npn-edit-intro";
import NpnField from "./npn-field";
import NpnLockedImages from "./npn-locked-images";
import NpnPhotoStage from "./npn-photo-stage";
import NpnPreviewModal from "./npn-preview-modal";

// New Members Area image submission form. A gentle, low-pressure way for
// newer members to share one nature image and invite basic feedback before
// they're ready for the full Image Critique categories.
//
// Intentionally simpler than the critique/project forms:
//   - No critique style, no feedback focus, no Technical Details.
//   - The photograph leads, on a mat, with its title as a caption (the look
//     of the photo-first critique form, without its extras).
//   - One open box (about the photograph); the question for members is a
//     one-line row until wanted.
//   - No tag chooser — this form doesn't apply any descriptive tags.
//   - Exactly one image (required), validated client- and server-side.
//   - A small collapsible "Need ideas for what to ask?" disclosure under the
//     feedback field. No prompt chips.
//   - Same draft autosave / Preview / Submit flow as the other forms.
//
// Data contract sent on submit / preview / draft:
//   {
//     submission_type: "new_member_image",
//     title: "...",
//     data: {
//       images: [{ upload_id, note: "" }],     // exactly 1 entry, required
//       fields: { about_this_image: "...", feedback: "..." }
//     }
//   }
//
// Reuses the established `about_this_image` field key (matches the Standard
// / In-Depth critique field). The feedback field uses `feedback` rather than
// `feedback_requested` because the post heading is "Feedback Welcome", not
// "Feedback Requested", and the two contracts should remain distinct.
export default class NpnNewMemberImageForm extends Component {
  @service router;
  @service modal;
  @service dialog;
  @service siteSettings;

  @tracked title = "";
  @tracked image = null; // the parsed /uploads.json response, or null
  @tracked fields = { about_this_image: "", feedback: "" };
  @tracked draftId = null;
  @tracked drafts = [];
  @tracked uploading = false;
  @tracked submitting = false;
  @tracked previewing = false;
  @tracked attemptedSubmit = false;
  @tracked feedbackExpanded = false;
  // Edit-with-form mode (/submit?edit=<id>): saves back over the published
  // post. See ../lib/npn-form-edit.js.
  editing = false;
  imagesLocked = false;
  editedOutsideForm = false;
  editSubmissionId = null;
  editTopicUrl = null;

  constructor() {
    super(...arguments);
    this.autosaver = new NpnDraftAutosaver({
      buildPayload: () => this.buildPayload(),
      hasContent: () => this.hasMeaningfulContent,
      getDraftId: () => this.draftId,
      setDraftId: (id) => {
        this.draftId = id;
      },
    });
    if (startEditing(this, this.args.editState)) {
      this.hydrate(this.args.editState.submission);
    } else {
      this.loadDrafts();
    }
  }

  willDestroy() {
    super.willDestroy(...arguments);
    this.autosaver.teardown();
  }

  // Target category for this submission type — gives DEditor category-scoped
  // @mention/#hashtag autocomplete. Stored as a string setting; null if unset.
  get categoryId() {
    return (
      parseInt(
        this.siteSettings.npn_submissions_new_member_image_category_id,
        10
      ) || null
    );
  }

  get hasMeaningfulContent() {
    return (
      this.title.trim().length > 0 ||
      !!this.image ||
      Object.values(this.fields).some((v) => (v || "").trim().length > 0)
    );
  }

  scheduleAutosave() {
    this.autosaver.schedule();
  }

  // --- Drafts ---------------------------------------------------------------

  async loadDrafts() {
    try {
      const result = await ajax("/npn-submissions/drafts");
      // Only this form's drafts; never mix with critique/intro drafts.
      this.drafts = (result.drafts || [])
        .filter((draft) => draft.submission_type === "new_member_image")
        .map((draft) => ({ ...draft, label: this.draftLabel(draft) }));
    } catch {
      this.drafts = [];
    }
  }

  draftLabel(draft) {
    const title = (draft.title || "").trim();
    if (title) {
      return title;
    }
    const date = draft.updated_at
      ? new Date(draft.updated_at).toLocaleDateString(undefined, {
          month: "short",
          day: "numeric",
        })
      : null;
    const untitled = i18n("npn_submissions.form.drafts.untitled");
    return date ? `${untitled} — ${date}` : untitled;
  }

  get resumableDrafts() {
    return this.drafts.filter((draft) => draft.id !== this.draftId);
  }

  get hasDrafts() {
    return this.resumableDrafts.length > 0;
  }

  // The single image, in NpnLockedImages' shape.
  get lockedImages() {
    return this.image ? [this.image] : [];
  }

  @action
  loadDraft(draft) {
    this.draftId = draft.id;
    this.hydrate(draft);
  }

  // Fill the form from a serialized submission (a draft, or a published post
  // being edited).
  hydrate(draft) {
    this.title = draft.title || "";
    const data = draft.data || {};
    this.fields = {
      about_this_image: data.fields?.about_this_image || "",
      feedback: data.fields?.feedback || "",
    };
    const firstImage = (draft.images || [])[0];
    this.image = firstImage
      ? {
          id: firstImage.id,
          url: firstImage.url,
          original_filename: firstImage.original_filename,
        }
      : null;
    this.attemptedSubmit = false;
    // NpnField is a controlled DEditor bound to `@value`, so reassigning
    // `this.fields` above seeds the editors directly — no DOM write needed.
  }

  @action
  async discardDraft(draft) {
    try {
      await ajax(`/npn-submissions/drafts/${draft.id}`, { type: "DELETE" });
      if (this.draftId === draft.id) {
        this.draftId = null;
      }
      this.drafts = this.drafts.filter((d) => d.id !== draft.id);
    } catch (e) {
      popupAjaxError(e);
    }
  }

  // --- Field handlers -------------------------------------------------------

  @action
  updateTitle(event) {
    this.title = event.target.value;
    this.scheduleAutosave();
  }

  @action
  updateField(key, event) {
    this.fields = { ...this.fields, [key]: event.target.value };
    this.scheduleAutosave();
  }

  // --- Image upload ---------------------------------------------------------

  @action
  async addImageFiles(files) {
    const file = files[0];
    if (!file) {
      return;
    }
    const upload = await this.uploadFile(file);
    if (upload) {
      await noteColourProfile(file, upload);
      this.image = upload;
      this.scheduleAutosave();
    }
  }

  @action
  removeImage() {
    this.image = null;
    this.scheduleAutosave();
  }

  async uploadFile(file) {
    const formData = new FormData();
    formData.append("upload_type", "composer");
    formData.append("file", file);
    this.uploading = true;
    try {
      return await ajax("/uploads.json", {
        type: "POST",
        data: formData,
        processData: false,
        contentType: false,
      });
    } catch (e) {
      popupAjaxError(e);
      return null;
    } finally {
      this.uploading = false;
    }
  }

  // --- Validation (mirror of server-side rules) -----------------------------

  get imageMissing() {
    return this.attemptedSubmit && !this.image;
  }

  get titleMissing() {
    return this.attemptedSubmit && this.title.trim().length === 0;
  }

  get aboutField() {
    return {
      key: "about_this_image",
      fieldId: "npn-field-about_this_image",
      label: i18n("npn_submissions.new_member_image.fields.about.label"),
      help: i18n("npn_submissions.new_member_image.fields.about.help"),
      required: false,
      optional: true,
      compact: true,
      error: null,
    };
  }

  get feedbackField() {
    return {
      key: "feedback",
      fieldId: "npn-field-feedback",
      label: i18n("npn_submissions.new_member_image.fields.feedback.label"),
      help: i18n("npn_submissions.new_member_image.fields.feedback.help"),
      required: false,
      optional: true,
      compact: true,
      error: null,
    };
  }

  // Questions a new member could borrow, added to the box on a tap.
  get askIdeas() {
    return [
      "notice_first",
      "balanced",
      "distracting",
      "processing",
      "stronger",
    ].map((key) => ({
      key,
      text: i18n(`npn_submissions.new_member_image.examples.${key}`),
    }));
  }

  // The question box is one line until wanted, or until it holds something.
  get feedbackOpen() {
    return (
      this.feedbackExpanded || (this.fields.feedback || "").trim().length > 0
    );
  }

  @action
  openFeedback() {
    this.feedbackExpanded = true;
  }

  @action
  addIdea(text) {
    const current = (this.fields.feedback || "").replace(/\s+$/, "");
    this.fields = {
      ...this.fields,
      feedback: current ? `${current}\n\n${text}` : text,
    };
    focusFieldBySelector(`#${this.feedbackField.fieldId}`);
    this.scheduleAutosave();
  }

  get canSubmitClientSide() {
    return !!this.image && this.title.trim().length > 0;
  }

  // --- Build / autosave payload ---------------------------------------------

  buildPayload() {
    return {
      submission_type: "new_member_image",
      critique_style: null,
      title: this.title,
      client_timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      data: {
        images: this.image ? [{ upload_id: this.image.id, note: "" }] : [],
        fields: this.fields,
      },
    };
  }

  // --- Actions: Save Draft / Preview / Submit -------------------------------

  @action
  saveDraft() {
    return this.autosaver.saveNow();
  }

  get busy() {
    return (
      this.uploading ||
      this.autosaver.isSaving ||
      this.submitting ||
      this.previewing
    );
  }

  @action
  async openPreview() {
    this.attemptedSubmit = true;
    if (!this.canSubmitClientSide) {
      this.focusFirstMissing();
      return;
    }

    this.previewing = true;
    try {
      const result = await ajax("/npn-submissions/preview", {
        type: "POST",
        contentType: "application/json",
        data: JSON.stringify(this.buildPayload()),
      });
      this.modal.show(NpnPreviewModal, {
        model: {
          title: this.title,
          cooked: result.cooked,
          markdown: result.markdown,
          tags: result.tags,
          submitDisabled: false,
          submitDisabledReason: null,
          submitLabel: this.editing
            ? "npn_submissions.form.edit.save"
            : "npn_submissions.new_member_image.submit",
          onSubmit: () => this.submit(),
        },
      });
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.previewing = false;
    }
  }

  @action
  async submit(event) {
    event?.preventDefault();
    if (this.editing) {
      return this.submitEdit();
    }
    this.attemptedSubmit = true;
    if (!this.canSubmitClientSide) {
      this.focusFirstMissing();
      return false;
    }

    this.submitting = true;
    try {
      const payload = this.buildPayload();
      if (this.draftId) {
        payload.draft_id = this.draftId;
      }
      const result = await ajax("/npn-submissions/submissions", {
        type: "POST",
        contentType: "application/json",
        data: JSON.stringify(payload),
      });
      const submission = result.submission;
      if (submission?.topic_url) {
        this.autosaver.stop();
        this.router.transitionTo(submission.topic_url);
        return true;
      }
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.submitting = false;
    }
    return false;
  }

  // Validate like Submit, then save over the published post.
  async submitEdit(force = false) {
    this.attemptedSubmit = true;
    if (!this.canSubmitClientSide) {
      this.focusFirstMissing();
      return false;
    }
    this.submitting = true;
    try {
      return await saveEdit(this, force);
    } finally {
      this.submitting = false;
    }
  }

  @action
  cancelEdit() {
    this.router.transitionTo(this.editTopicUrl);
  }

  focusFirstMissing() {
    let selector;
    if (!this.image) {
      selector = "#npn-new-member-image-field input[type='file']";
    } else if (this.title.trim().length === 0) {
      selector = "#npn-title";
    }
    if (selector) {
      focusFieldBySelector(selector);
    }
  }

  // --- Start new ------------------------------------------------------------

  get showStartNew() {
    return (!this.editing && !!this.draftId) || this.hasMeaningfulContent;
  }

  @action
  startNew() {
    if (
      this.autosaver.status === "failed" ||
      this.autosaver.hasPendingChanges
    ) {
      this.dialog.confirm({
        message: i18n("npn_submissions.form.drafts.start_new_confirm"),
        confirmButtonLabel:
          "npn_submissions.form.drafts.start_new_confirm_button",
        didConfirm: () => this.resetForm(),
      });
    } else {
      this.resetForm();
    }
  }

  resetForm() {
    this.autosaver.reset();
    this.draftId = null;
    this.title = "";
    this.image = null;
    this.fields = { about_this_image: "", feedback: "" };
    this.attemptedSubmit = false;
    this.feedbackExpanded = false;
    this.loadDrafts();
  }

  <template>
    <form
      class="npn-image-form npn-photo-form npn-new-member-image-form"
      {{on "submit" this.submit}}
    >
      <header class="npn-image-form__intro">
        {{#if this.editing}}
          <NpnEditIntro @editedOutsideForm={{this.editedOutsideForm}} />
        {{else}}
          <h2>{{i18n "npn_submissions.new_member_image.intro.title"}}</h2>
          <p class="npn-image-form__lead">
            {{i18n "npn_submissions.new_member_image.intro.lead"}}
          </p>
        {{/if}}
      </header>

      {{#if this.hasDrafts}}
        <details class="npn-image-form__drafts">
          <summary>
            {{i18n
              "npn_submissions.form.drafts.summary"
              count=this.resumableDrafts.length
            }}
          </summary>
          <div class="npn-image-form__drafts-body">
            <p class="npn-help">{{i18n "npn_submissions.form.drafts.help"}}</p>
            <ul class="npn-image-form__draft-list">
              {{#each this.resumableDrafts as |draft|}}
                <li class="npn-image-form__draft">
                  <DButton
                    @translatedLabel={{draft.label}}
                    @action={{fn this.loadDraft draft}}
                    class="btn-default npn-image-form__draft-load"
                  />
                  <DButton
                    @icon="trash-can"
                    @action={{fn this.discardDraft draft}}
                    @title="npn_submissions.form.drafts.discard"
                    class="btn-flat"
                  />
                </li>
              {{/each}}
            </ul>
          </div>
        </details>
      {{/if}}

      {{#if this.showStartNew}}
        <div class="npn-image-form__start-new">
          <DButton
            @label="npn_submissions.new_member_image.start_new"
            @action={{this.startNew}}
            @icon="plus"
            class="btn-default npn-image-form__start-new-button"
          />
        </div>
      {{/if}}

      {{! The photograph — exactly one, required — with its title as caption. }}
      <div
        id="npn-new-member-image-field"
        class={{if this.imageMissing "needs-attention"}}
      >
        {{#if this.imagesLocked}}
          <NpnLockedImages
            @images={{this.lockedImages}}
            @noticeKey="npn_submissions.form.edit.image_locked_feedback"
          />
        {{else}}
          <NpnPhotoStage
            @image={{this.image}}
            @uploading={{this.uploading}}
            @label={{i18n
              "npn_submissions.new_member_image.fields.image.upload_label"
            }}
            @onFiles={{this.addImageFiles}}
            @onRemove={{this.removeImage}}
          />
        {{/if}}
        {{#if this.imageMissing}}
          <p class="npn-image-form__prompt" aria-live="polite">
            {{i18n "npn_submissions.new_member_image.prompts.add_image"}}
          </p>
        {{/if}}
      </div>

      <div
        class="npn-photo-form__caption
          {{if this.titleMissing 'needs-attention'}}"
      >
        <input
          id="npn-title"
          class="npn-photo-form__title"
          type="text"
          value={{this.title}}
          placeholder={{i18n "npn_submissions.photo_form.title_placeholder"}}
          aria-label={{i18n
            "npn_submissions.new_member_image.fields.title.label"
          }}
          aria-required="true"
          {{on "input" this.updateTitle}}
        />
        {{#if this.titleMissing}}
          <p class="npn-image-form__prompt" aria-live="polite">
            {{i18n "npn_submissions.form.prompts.enter_title"}}
          </p>
        {{/if}}
      </div>

      <div class="npn-photo-form__simple-fields">
        {{! About this photograph — optional, the one open box }}
        <NpnField
          @fieldId={{this.aboutField.fieldId}}
          @label={{this.aboutField.label}}
          @help={{this.aboutField.help}}
          @optional={{this.aboutField.optional}}
          @compact={{this.aboutField.compact}}
          @value={{this.fields.about_this_image}}
          @categoryId={{this.categoryId}}
          @onChange={{fn this.updateField this.aboutField.key}}
        />

        {{! A question for members — optional, one line until wanted }}
        {{#if this.feedbackOpen}}
          <NpnField
            @fieldId={{this.feedbackField.fieldId}}
            @label={{this.feedbackField.label}}
            @help={{this.feedbackField.help}}
            @optional={{this.feedbackField.optional}}
            @compact={{this.feedbackField.compact}}
            @value={{this.fields.feedback}}
            @categoryId={{this.categoryId}}
            @onChange={{fn this.updateField this.feedbackField.key}}
          >
            <NpnAskIdeas
              @ideas={{this.askIdeas}}
              @summary={{i18n
                "npn_submissions.photo_form.ideas.reaction_summary"
              }}
              @onPick={{this.addIdea}}
            />
          </NpnField>
        {{else}}
          <button
            type="button"
            class="npn-photo-form__add-row"
            {{on "click" this.openFeedback}}
          >
            {{dIcon "plus"}}
            <span>
              {{i18n "npn_submissions.new_member_image.fields.feedback.add"}}
            </span>
            <span class="npn-photo-form__add-row-note">
              {{i18n "npn_submissions.photo_form.optional"}}
            </span>
          </button>
        {{/if}}
      </div>

      <p class="npn-image-form__participation">
        {{i18n "npn_submissions.new_member_image.submit_note"}}
      </p>

      <div class="npn-image-form__actions">
        {{#if this.editing}}
          <DButton
            @label="npn_submissions.form.edit.cancel"
            @action={{this.cancelEdit}}
            @disabled={{this.submitting}}
            class="btn-default"
          />
        {{else}}
          <DButton
            @label="npn_submissions.form.save_draft"
            @action={{this.saveDraft}}
            @disabled={{this.busy}}
            @isLoading={{this.autosaver.isSaving}}
            class="btn-default"
          />
        {{/if}}
        <DButton
          @label="npn_submissions.form.preview.button"
          @action={{this.openPreview}}
          @disabled={{this.busy}}
          @isLoading={{this.previewing}}
          class="btn-default"
        />
        <DButton
          @label={{if
            this.editing
            "npn_submissions.form.edit.save"
            "npn_submissions.new_member_image.submit"
          }}
          @action={{this.submit}}
          @disabled={{this.busy}}
          @isLoading={{this.submitting}}
          class="btn-primary"
        />
      </div>

      {{#unless this.editing}}
        <NpnAutosaveStatus @autosaver={{this.autosaver}} />
        <p class="npn-help npn-image-form__draft-return-hint">
          {{i18n "npn_submissions.form.drafts.return_hint"}}
        </p>
      {{/unless}}
    </form>
  </template>
}
