import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import { collectDiagnostics, formatDiagnostics } from "../lib/npn-diagnostics";
import NpnDraftAutosaver from "../lib/npn-draft-autosaver";
import { focusFieldBySelector } from "../lib/npn-focus-field";
import NpnAutosaveStatus from "./npn-autosave-status";
import NpnField from "./npn-field";
import NpnImageList from "./npn-image-list";
import NpnPreviewModal from "./npn-preview-modal";

const MAX_SCREENSHOTS = 3;

// "Ask for Help" submission form. A small structured form for members who
// need help with the site/plugin. Intentionally lighter than the critique
// forms: a one-line summary that becomes the topic title, a free-form
// description, optional screenshots (0–3), and an optional diagnostic-info
// block that the form auto-collects (browser, OS, device + viewport,
// same-origin referrer).
//
// Diagnostic info collection is client-side only, default ON with a clearly
// visible opt-out checkbox; the user sees exactly what would be posted in
// a preview row below the checkbox before they submit. When the checkbox
// is off, the diagnostic field is empty and the server's HelpPostBuilder
// emits no [details] block.
//
// Data contract sent on submit / preview / draft:
//   {
//     submission_type: "help",
//     title: "<the title field>",
//     data: {
//       images: [{ upload_id, note }, …],   // 0–3 screenshots
//       fields: {
//         description:     "<textarea body>",
//         diagnostic_info: "<pre-formatted Markdown bullet list, or empty>"
//       }
//     }
//   }
//
// The form treats the title input separately from the textarea so the
// topic title is one clean line; auto-deriving a title from a free-form
// help paragraph reads poorly in topic lists.
export default class NpnHelpForm extends Component {
  @service router;
  @service modal;
  @service dialog;
  @service siteSettings;

  @tracked title = "";
  @tracked fields = { description: "" };
  @tracked images = []; // [{ upload, note }] — same shape as NpnImageList
  @tracked includeDiagnostics = true;
  // Recomputed once on construction. The DOM contract these read (window
  // size, document.referrer, navigator.userAgent[Data]) doesn't change
  // during the form's lifetime — and capturing at construction time gives
  // us a stable preview value the user can review before submit.
  @tracked diagnostics = collectDiagnostics();
  @tracked draftId = null;
  @tracked drafts = [];
  @tracked uploading = false;
  @tracked submitting = false;
  @tracked previewing = false;
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

  // Target category for this submission type — gives DEditor category-scoped
  // @mention/#hashtag autocomplete. Stored as a string setting; null if unset.
  get categoryId() {
    return (
      parseInt(this.siteSettings.npn_submissions_help_category_id, 10) || null
    );
  }

  get hasMeaningfulContent() {
    return (
      this.title.trim().length > 0 ||
      this.images.length > 0 ||
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
      // Help drafts only; never mix with other submission-type drafts.
      this.drafts = (result.drafts || [])
        .filter((draft) => draft.submission_type === "help")
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
    this.fields = { description: data.fields?.description || "" };
    this.images = (draft.images || []).map((img) => ({
      upload: {
        id: img.id,
        url: img.url,
        original_filename: img.original_filename,
      },
      note: img.note || "",
    }));
    // Drafts don't preserve the diagnostic toggle — recapture fresh each
    // time the form is reopened so the values reflect the current device.
    this.diagnostics = collectDiagnostics();
    this.includeDiagnostics = true;
    this.attemptedSubmit = false;
    // NpnField is a controlled DEditor bound to `@value`, so reassigning
    // `this.fields` above seeds the editor directly — no DOM write needed.
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

  @action
  toggleDiagnostics(event) {
    this.includeDiagnostics = !!event.target.checked;
    this.scheduleAutosave();
  }

  // --- Screenshot uploads ---------------------------------------------------

  @action
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

  @action
  setImages(next) {
    this.images = next;
    this.scheduleAutosave();
  }

  // --- Validation -----------------------------------------------------------

  get titleMissing() {
    return this.attemptedSubmit && this.title.trim().length === 0;
  }

  get descriptionMissing() {
    return (
      this.attemptedSubmit &&
      (this.fields.description || "").trim().length === 0
    );
  }

  get descriptionField() {
    return {
      key: "description",
      fieldId: "npn-field-description",
      label: i18n("npn_submissions.help.fields.description.label"),
      help: i18n("npn_submissions.help.fields.description.help"),
      required: true,
      error: this.descriptionMissing
        ? i18n("npn_submissions.form.field_required")
        : null,
    };
  }

  get diagnosticLabels() {
    return {
      browser: i18n("npn_submissions.help.diagnostics.fields.browser"),
      os: i18n("npn_submissions.help.diagnostics.fields.os"),
      device: i18n("npn_submissions.help.diagnostics.fields.device"),
      referrer: i18n("npn_submissions.help.diagnostics.fields.referrer"),
    };
  }

  // The pre-formatted diagnostic Markdown the server will wrap in [details],
  // or the empty string when the user has opted out. The "what will be
  // posted" preview row below the checkbox renders from the SAME source so
  // the user sees exactly what's about to be sent.
  get diagnosticMarkdown() {
    if (!this.includeDiagnostics) {
      return "";
    }
    return formatDiagnostics(this.diagnostics, this.diagnosticLabels);
  }

  // Same content, parsed back into an array for the in-form preview rows.
  // Hidden when the user has opted out.
  get diagnosticPreviewRows() {
    if (!this.includeDiagnostics) {
      return [];
    }
    const labels = this.diagnosticLabels;
    const rows = [];
    if (this.diagnostics.browser) {
      rows.push({ label: labels.browser, value: this.diagnostics.browser });
    }
    if (this.diagnostics.os) {
      rows.push({ label: labels.os, value: this.diagnostics.os });
    }
    if (this.diagnostics.device) {
      rows.push({ label: labels.device, value: this.diagnostics.device });
    }
    if (this.diagnostics.referrer) {
      rows.push({ label: labels.referrer, value: this.diagnostics.referrer });
    }
    return rows;
  }

  get canSubmitClientSide() {
    return (
      this.title.trim().length > 0 &&
      (this.fields.description || "").trim().length > 0
    );
  }

  get maxScreenshots() {
    return MAX_SCREENSHOTS;
  }

  // --- Build / autosave payload ---------------------------------------------

  buildPayload() {
    return {
      submission_type: "help",
      critique_style: null,
      title: this.title,
      client_timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      data: {
        images: this.images.map((entry) => ({
          upload_id: entry.upload.id,
          note: entry.note || "",
        })),
        fields: {
          description: this.fields.description,
          diagnostic_info: this.diagnosticMarkdown,
        },
      },
    };
  }

  // --- Actions --------------------------------------------------------------

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
          submitLabel: "npn_submissions.help.submit",
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
    } else if ((this.fields.description || "").trim().length === 0) {
      selector = "#npn-field-description";
    }
    if (selector) {
      focusFieldBySelector(selector);
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
    this.images = [];
    this.fields = { description: "" };
    this.diagnostics = collectDiagnostics();
    this.includeDiagnostics = true;
    this.attemptedSubmit = false;
    this.loadDrafts();
  }

  <template>
    <form class="npn-image-form npn-help-form" {{on "submit" this.submit}}>
      <header class="npn-image-form__intro">
        <h2>{{i18n "npn_submissions.help.intro.title"}}</h2>
        <p class="npn-image-form__lead">
          {{i18n "npn_submissions.help.intro.lead"}}
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
            @label="npn_submissions.help.start_new"
            @action={{this.startNew}}
            @icon="plus"
            class="btn-default npn-image-form__start-new-button"
          />
        </div>
      {{/if}}

      {{! Title — required }}
      <div
        class="npn-image-form__field
          {{if this.titleMissing 'npn-image-form__field--needs-attention'}}"
      >
        <label for="npn-title">
          {{i18n "npn_submissions.help.fields.title.label"}}
          <span class="npn-required">{{i18n
              "npn_submissions.form.required"
            }}</span>
        </label>
        <p class="npn-help">{{i18n
            "npn_submissions.help.fields.title.help"
          }}</p>
        <input
          id="npn-title"
          type="text"
          value={{this.title}}
          {{on "input" this.updateTitle}}
        />
      </div>

      {{! Description — required }}
      <NpnField
        @fieldId={{this.descriptionField.fieldId}}
        @label={{this.descriptionField.label}}
        @help={{this.descriptionField.help}}
        @required={{this.descriptionField.required}}
        @error={{this.descriptionField.error}}
        @value={{this.fields.description}}
        @categoryId={{this.categoryId}}
        @onChange={{fn this.updateField this.descriptionField.key}}
      />

      {{! Screenshots — optional, up to 3 with optional captions/reorder }}
      <div class="npn-image-form__field">
        <label>
          {{i18n "npn_submissions.help.fields.screenshots.label"}}
          <span class="npn-optional">{{i18n
              "npn_submissions.form.optional"
            }}</span>
        </label>
        <p class="npn-help">{{i18n
            "npn_submissions.help.fields.screenshots.help"
          }}</p>

        <NpnImageList
          @images={{this.images}}
          @onChange={{this.setImages}}
          @uploadFile={{this.uploadFile}}
          @uploading={{this.uploading}}
          @maxImages={{this.maxScreenshots}}
          @uploadLabel={{i18n
            "npn_submissions.help.fields.screenshots.upload_label"
          }}
          @addMoreLabel={{i18n
            "npn_submissions.help.fields.screenshots.add_more"
          }}
          @addMoreHelp={{i18n
            "npn_submissions.help.fields.screenshots.add_more_help"
          }}
          @enableNotes={{true}}
          @notePlaceholder={{i18n
            "npn_submissions.help.fields.screenshots.note_placeholder"
          }}
        />
      </div>

      {{! Diagnostic info toggle + preview }}
      <div class="npn-image-form__field npn-help-form__diagnostics">
        <label class="npn-help-form__diagnostics-toggle">
          <input
            type="checkbox"
            checked={{this.includeDiagnostics}}
            {{on "change" this.toggleDiagnostics}}
          />
          <span>{{i18n "npn_submissions.help.diagnostics.label"}}</span>
        </label>
        <p class="npn-help">{{i18n "npn_submissions.help.diagnostics.help"}}</p>

        {{#if this.includeDiagnostics}}
          <div class="npn-help-form__diagnostics-preview">
            <p class="npn-help-form__diagnostics-preview-heading">
              {{i18n "npn_submissions.help.diagnostics.preview_heading"}}
            </p>
            <ul>
              {{#each this.diagnosticPreviewRows as |row|}}
                <li>
                  <strong>{{row.label}}:</strong>
                  {{row.value}}
                </li>
              {{/each}}
            </ul>
          </div>
        {{/if}}
      </div>

      <p class="npn-image-form__participation">
        {{i18n "npn_submissions.help.submit_note"}}
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
          @label="npn_submissions.help.submit"
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
