import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { schedule } from "@ember/runloop";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import NpnDraftAutosaver from "../lib/npn-draft-autosaver";
import NpnAutosaveStatus from "./npn-autosave-status";
import NpnField from "./npn-field";
import NpnPreviewModal from "./npn-preview-modal";
import NpnUploadZone from "./npn-upload-zone";

// New-member introduction submission form. Intentionally simpler and lower-
// pressure than the critique/project forms:
//
//   - No critique style, no feedback focus, no chips, no Technical Details.
//   - No tag chooser — introductions don't apply any descriptive tags.
//   - One optional image (no per-image notes, no reorder, no EXIF).
//   - Daily-limit notice is not shown — introductions don't count against the
//     critique daily limit (handled server-side in DailyLimit#reached?).
//   - Same draft autosave / Preview / Submit flow as the other forms, so the
//     submission infrastructure (DraftStore, Submitter, PostBuilder) is reused.
//
// Data contract sent on submit / preview / draft:
//   {
//     submission_type: "introduction",
//     title: "...",
//     data: {
//       images: [{ upload_id, note: "" }],   // 0 or 1 entry
//       fields: { about: "...", learning: "..." },
//     },
//   }
//
// `images` reuses the same shape as the critique forms so Submission#image_
// entries works unchanged; `fields.about` is required server-side,
// `fields.learning` is optional.
export default class NpnIntroductionForm extends Component {
  @service router;
  @service modal;
  @service dialog;

  @tracked title = "";
  @tracked image = null; // single optional upload (the parsed /uploads.json response)
  @tracked fields = { about: "", learning: "" };
  @tracked draftId = null;
  @tracked drafts = [];
  @tracked uploading = false;
  @tracked submitting = false;
  @tracked previewing = false;
  // Set once the user attempts to submit, so inline guidance escalates.
  @tracked attemptedSubmit = false;

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
    this.loadDrafts();
  }

  willDestroy() {
    super.willDestroy(...arguments);
    this.autosaver.teardown();
  }

  // Autosave starts only once there's something worth keeping.
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
      // Only show introduction drafts in this form's resume panel; never mix
      // critique drafts in here.
      this.drafts = (result.drafts || [])
        .filter((draft) => draft.submission_type === "introduction")
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

  @action
  loadDraft(draft) {
    this.draftId = draft.id;
    this.title = draft.title || "";
    const data = draft.data || {};
    this.fields = {
      about: data.fields?.about || "",
      learning: data.fields?.learning || "",
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

    // The textareas are uncontrolled inside NpnField; write values after the
    // fields render.
    schedule("afterRender", this, () => {
      Object.entries(this.fields).forEach(([key, value]) => {
        const el = document.getElementById(`npn-field-${key}`);
        if (el) {
          el.value = value ?? "";
        }
      });
    });
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

  get titleMissing() {
    return this.attemptedSubmit && this.title.trim().length === 0;
  }

  get aboutMissing() {
    return (
      this.attemptedSubmit && (this.fields.about || "").trim().length === 0
    );
  }

  // Inline labels match the field key (npn-field-${key}) so the validation
  // summary can deep-scroll.
  get titleFieldProps() {
    return {
      key: "title",
      fieldId: "npn-title",
      missing: this.titleMissing,
    };
  }

  get aboutField() {
    return {
      key: "about",
      fieldId: "npn-field-about",
      label: i18n("npn_submissions.introduction.fields.about.label"),
      help: i18n("npn_submissions.introduction.fields.about.help"),
      required: true,
      optional: false,
      error: this.aboutMissing
        ? i18n("npn_submissions.form.field_required")
        : null,
    };
  }

  get learningField() {
    return {
      key: "learning",
      fieldId: "npn-field-learning",
      label: i18n("npn_submissions.introduction.fields.learning.label"),
      help: i18n("npn_submissions.introduction.fields.learning.help"),
      required: false,
      optional: true,
      compact: true,
      error: null,
    };
  }

  get canSubmitClientSide() {
    return (
      this.title.trim().length > 0 &&
      (this.fields.about || "").trim().length > 0
    );
  }

  // --- Build / autosave payload ---------------------------------------------

  buildPayload() {
    return {
      submission_type: "introduction",
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
          submitLabel: "npn_submissions.introduction.submit",
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

  focusFirstMissing() {
    let selector;
    if (this.title.trim().length === 0) {
      selector = "#npn-title";
    } else if ((this.fields.about || "").trim().length === 0) {
      selector = "#npn-field-about";
    }
    if (selector) {
      document.querySelector(selector)?.focus({ preventScroll: true });
    }
  }

  // --- Start new ------------------------------------------------------------

  get showStartNew() {
    return !!this.draftId || this.hasMeaningfulContent;
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
    this.fields = { about: "", learning: "" };
    this.attemptedSubmit = false;
    this.loadDrafts();
  }

  <template>
    <form
      class="npn-image-form npn-introduction-form"
      {{on "submit" this.submit}}
    >
      <header class="npn-image-form__intro">
        <h2>{{i18n "npn_submissions.introduction.intro.title"}}</h2>
        <p class="npn-image-form__lead">
          {{i18n "npn_submissions.introduction.intro.lead"}}
        </p>
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
            @label="npn_submissions.introduction.start_new"
            @action={{this.startNew}}
            @icon="plus"
            class="btn-default npn-image-form__start-new-button"
          />
        </div>
      {{/if}}

      {{! Title }}
      <div
        class="npn-image-form__field
          {{if this.titleMissing 'npn-image-form__field--needs-attention'}}"
      >
        <label for="npn-title">
          {{i18n "npn_submissions.introduction.fields.title.label"}}
          <span class="npn-required">{{i18n
              "npn_submissions.form.required"
            }}</span>
        </label>
        <p class="npn-help">{{i18n
            "npn_submissions.introduction.fields.title.help"
          }}</p>
        <input
          id="npn-title"
          type="text"
          value={{this.title}}
          {{on "input" this.updateTitle}}
        />
      </div>

      {{! About You — required }}
      <NpnField
        @fieldId={{this.aboutField.fieldId}}
        @label={{this.aboutField.label}}
        @help={{this.aboutField.help}}
        @required={{this.aboutField.required}}
        @error={{this.aboutField.error}}
        @onInput={{fn this.updateField this.aboutField.key}}
      />

      {{! Learning — optional, compact }}
      <NpnField
        @fieldId={{this.learningField.fieldId}}
        @label={{this.learningField.label}}
        @help={{this.learningField.help}}
        @optional={{this.learningField.optional}}
        @compact={{this.learningField.compact}}
        @onInput={{fn this.updateField this.learningField.key}}
      />

      {{! Optional image — single upload }}
      <div class="npn-image-form__field npn-introduction-form__image-field">
        <label>
          {{i18n "npn_submissions.introduction.fields.image.label"}}
          <span class="npn-optional">{{i18n
              "npn_submissions.form.optional"
            }}</span>
        </label>
        <p class="npn-help">{{i18n
            "npn_submissions.introduction.fields.image.help"
          }}</p>

        {{#if this.image}}
          <div class="npn-image-form__image-row">
            <div class="npn-image-form__thumb">
              <img
                src={{this.image.url}}
                alt={{this.image.original_filename}}
              />
            </div>
            <DButton
              @icon="trash-can"
              @action={{this.removeImage}}
              @title="npn_submissions.form.images.remove"
              @ariaLabel="npn_submissions.form.images.remove"
              class="btn-flat"
            />
          </div>
        {{else}}
          <NpnUploadZone
            @accept="image/*"
            @disabled={{this.uploading}}
            @label={{i18n
              "npn_submissions.introduction.fields.image.upload_label"
            }}
            @onFiles={{this.addImageFiles}}
          />
        {{/if}}
      </div>

      <p class="npn-image-form__participation">
        {{i18n "npn_submissions.introduction.submit_note"}}
      </p>

      <div class="npn-image-form__actions">
        <DButton
          @label="npn_submissions.form.save_draft"
          @action={{this.saveDraft}}
          @disabled={{this.busy}}
          @isLoading={{this.autosaver.isSaving}}
          class="btn-default"
        />
        <DButton
          @label="npn_submissions.form.preview.button"
          @action={{this.openPreview}}
          @disabled={{this.busy}}
          @isLoading={{this.previewing}}
          class="btn-default"
        />
        <DButton
          @label="npn_submissions.introduction.submit"
          @action={{this.submit}}
          @disabled={{this.busy}}
          @isLoading={{this.submitting}}
          class="btn-primary"
        />
      </div>

      <NpnAutosaveStatus @autosaver={{this.autosaver}} />
      <p class="npn-help npn-image-form__draft-return-hint">
        {{i18n "npn_submissions.form.drafts.return_hint"}}
      </p>
    </form>
  </template>
}
