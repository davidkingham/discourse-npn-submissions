import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn, hash } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { schedule } from "@ember/runloop";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import ComboBox from "discourse/select-kit/components/combo-box";
import MultiSelect from "discourse/select-kit/components/multi-select";
import TagChooser from "discourse/select-kit/components/tag-chooser";
import { eq } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import NpnDraftAutosaver from "../lib/npn-draft-autosaver";
import NpnAutosaveStatus from "./npn-autosave-status";
import NpnExpandableExample from "./npn-expandable-example";
import NpnField from "./npn-field";
import NpnImageList from "./npn-image-list";
import NpnPreviewModal from "./npn-preview-modal";
import NpnUploadZone from "./npn-upload-zone";

const METHODS = ["images", "pdf", "url"];
const FOCUSES = ["artistic", "technical", "both"];
const INTENTS = ["gallery", "lwfull", "lwis", "on", "magazine", "web", "book", "fun", "other"];

// Project-specific Feedback Requested examples, keyed by feedback focus. Keys map
// to i18n entries under form.project.examples.feedback.<focus>.items.*
const FOCUS_EXAMPLE_KEYS = {
  artistic: ["cohesive", "belong", "communicate", "weaker", "rhythm", "consistent"],
  technical: ["processing", "weaker_tech", "exposure", "presentation", "format", "layout"],
  both: ["cohesive", "weaker", "communicate", "processing", "weaker_tech", "presentation"],
};

// Project Critique: a body of work (uploaded images, a PDF, or a link) with a
// fixed set of reflective questions. Reuses the shared upload/list, field,
// preview-modal, draft, daily-limit and tag-constraint patterns; the project
// post markdown is built server-side by ProjectPostBuilder.
export default class NpnProjectForm extends Component {
  @service router;
  @service siteSettings;
  @service modal;
  @service dialog;

  @tracked title = "";
  @tracked method = null;
  @tracked feedbackFocus = null;
  @tracked images = [];
  @tracked alternates = [];
  @tracked pdfUpload = null;
  // Required for PDF / URL projects so the topic has a thumbnail in topic lists.
  @tracked representativeImage = null;
  @tracked linkUrl = "";
  @tracked linkDescription = "";
  @tracked tags = [];
  @tracked tagsConstrained = false;
  @tracked allowedTags = [];
  @tracked fields = {};
  @tracked draftId = null;
  @tracked drafts = [];
  @tracked uploading = false;
  @tracked submitting = false;
  @tracked previewing = false;
  @tracked limitReached = false;
  @tracked attemptedSubmit = false;

  constructor() {
    super(...arguments);
    this.autosaver = new NpnDraftAutosaver({
      buildPayload: () => this.buildPayload(),
      hasContent: () => this.hasMeaningfulContent,
      getDraftId: () => this.draftId,
      // No loadDrafts here: the new draft is the active one and is excluded from
      // the resume list, so refreshing would only risk a layout jump.
      setDraftId: (id) => {
        this.draftId = id;
      },
    });
    this.loadDrafts();
    this.loadDailyLimit();
    this.loadDescriptiveTags();
  }

  willDestroy() {
    super.willDestroy(...arguments);
    this.autosaver.teardown();
  }

  // Autosave begins only once there's something worth keeping.
  get hasMeaningfulContent() {
    return (
      this.title.trim().length > 0 ||
      !!this.method ||
      this.images.length > 0 ||
      this.alternates.length > 0 ||
      !!this.pdfUpload ||
      !!this.representativeImage ||
      this.linkUrl.trim().length > 0 ||
      this.linkDescription.trim().length > 0 ||
      this.tags.length > 0 ||
      !!this.feedbackFocus ||
      Object.values(this.fields).some((v) => (v || "").trim().length > 0)
    );
  }

  scheduleAutosave() {
    this.autosaver.schedule();
  }

  // --- Init fetches ----------------------------------------------------------

  async loadDrafts() {
    try {
      const result = await ajax("/npn-submissions/drafts");
      this.drafts = (result.drafts || [])
        .filter((draft) => draft.submission_type === "project")
        .map((draft) => ({ ...draft, label: this.draftLabel(draft) }));
    } catch {
      this.drafts = [];
    }
  }

  async loadDailyLimit() {
    try {
      const tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
      const result = await ajax("/npn-submissions/daily-limit", { data: { tz } });
      this.limitReached = !!result.limit_reached;
    } catch {
      this.limitReached = false;
    }
  }

  async loadDescriptiveTags() {
    try {
      const result = await ajax("/npn-submissions/descriptive-tags");
      this.tagsConstrained = !!result.constrained;
      this.allowedTags = result.tags || [];
    } catch {
      this.tagsConstrained = false;
      this.allowedTags = [];
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

  // Drafts the user could resume — excludes the one they're actively editing, so
  // the panel doesn't pop in (and jump the layout) when autosave creates it.
  get resumableDrafts() {
    return this.drafts.filter((draft) => draft.id !== this.draftId);
  }

  get hasDrafts() {
    return this.resumableDrafts.length > 0;
  }

  get guidelinesUrl() {
    return this.siteSettings.npn_submissions_project_guidelines_url;
  }

  get siteSupportUrl() {
    return this.siteSettings.npn_submissions_site_support_url;
  }

  // --- Cards / options -------------------------------------------------------

  get methodCards() {
    return METHODS.map((id) => ({
      id,
      title: i18n(`npn_submissions.form.project.methods.${id}.title`),
      description: i18n(`npn_submissions.form.project.methods.${id}.description`),
    }));
  }

  get focusCards() {
    return FOCUSES.map((id) => ({
      id,
      title: i18n(`npn_submissions.form.project.focuses.${id}.title`),
      description: i18n(`npn_submissions.form.project.focuses.${id}.description`),
    }));
  }

  get intentOptions() {
    return INTENTS.map((id) => ({
      id,
      name: i18n(`npn_submissions.form.project.intents.${id}`),
    }));
  }

  get intentValue() {
    return this.fields.project_intent || null;
  }

  // --- Tag chooser -----------------------------------------------------------

  get allowedTagContent() {
    return this.allowedTags.map((name) => ({ id: name, name }));
  }

  // --- Image limits / warnings ----------------------------------------------

  get maxImages() {
    return parseInt(this.siteSettings.npn_submissions_max_project_images, 10) || 12;
  }

  get minImages() {
    return parseInt(this.siteSettings.npn_submissions_min_project_images, 10) || 6;
  }

  get maxAlternates() {
    return 6;
  }

  // Upload ids in each list, so the two lists can exclude each other's images
  // and the same file can't be both a project image and an alternate.
  get imageUploadIds() {
    return this.images.map((entry) => entry.upload.id);
  }

  get alternateUploadIds() {
    return this.alternates.map((entry) => entry.upload.id);
  }

  // Soft, non-blocking recommendation: warn when the member has added at least
  // one image but fewer than the recommended minimum.
  get belowRecommendedImages() {
    return (
      this.method === "images" &&
      this.images.length > 0 &&
      this.images.length < this.minImages
    );
  }

  // --- Feedback Requested examples (adapt to focus) --------------------------

  get feedbackExampleProps() {
    const focus = this.feedbackFocus;
    if (!focus) {
      return { neutral: i18n("npn_submissions.form.project.examples.feedback.neutral") };
    }
    return {
      summary: i18n(`npn_submissions.form.project.examples.feedback.${focus}.summary`),
      items: (FOCUS_EXAMPLE_KEYS[focus] || []).map((key) =>
        i18n(`npn_submissions.form.project.examples.feedback.${focus}.items.${key}`)
      ),
    };
  }

  // --- Field definitions -----------------------------------------------------

  field(key, { labelKey, helpKey = null, required = false, examples = null }) {
    const missing =
      required &&
      this.attemptedSubmit &&
      (this.fields[key] || "").trim().length === 0;
    return {
      key,
      fieldId: `npn-field-${key}`,
      label: i18n(`npn_submissions.form.project.fields.${labelKey}.label`),
      help: helpKey
        ? i18n(`npn_submissions.form.project.fields.${helpKey}.help`)
        : null,
      required,
      examples,
      error: missing ? i18n("npn_submissions.form.field_required") : null,
    };
  }

  // Project Description comes before the feedback focus (per the product flow).
  get descriptionField() {
    return this.field("project_description", {
      labelKey: "project_description",
      helpKey: "project_description",
      required: true,
    });
  }

  // Rendered after the feedback focus, since Feedback Requested adapts to it.
  get postFocusFields() {
    return [
      this.field("self_critique", { labelKey: "self_critique", required: true }),
      this.field("creative_direction", {
        labelKey: "creative_direction",
        helpKey: "creative_direction",
        required: true,
      }),
      this.field("feedback_requested", {
        labelKey: "feedback_requested",
        helpKey: "feedback_requested",
        required: true,
        examples: this.feedbackExampleProps,
      }),
    ];
  }

  // --- State helpers ---------------------------------------------------------

  get busy() {
    return (
      this.uploading ||
      this.autosaver.isSaving ||
      this.submitting ||
      this.previewing
    );
  }

  get submitDisabled() {
    return this.busy || this.limitReached;
  }

  get pdfFileLabel() {
    if (!this.pdfUpload) {
      return null;
    }
    const size = this.pdfUpload.human_filesize;
    return size
      ? `${this.pdfUpload.original_filename} (${size})`
      : this.pdfUpload.original_filename;
  }

  get mediaComplete() {
    if (this.method === "images") {
      return this.images.length > 0;
    }
    if (this.method === "pdf") {
      return !!this.pdfUpload && !!this.representativeImage;
    }
    if (this.method === "url") {
      return this.isValidUrl(this.linkUrl) && !!this.representativeImage;
    }
    return false;
  }

  // PDF/URL projects require a representative image; uploaded-image projects do
  // not (the first image represents the topic).
  get needsRepresentativeImage() {
    return this.method === "pdf" || this.method === "url";
  }

  isValidUrl(value) {
    const url = (value || "").trim();
    if (!url) {
      return false;
    }
    try {
      const parsed = new URL(url);
      return parsed.protocol === "http:" || parsed.protocol === "https:";
    } catch {
      return false;
    }
  }

  // Per-field "needs attention" flags, true only after a submit attempt. Drive
  // the red highlight on the non-NpnField fields (the NpnFields use @error).
  get titleMissing() {
    return this.attemptedSubmit && this.title.trim().length === 0;
  }

  get methodMissing() {
    return this.attemptedSubmit && !this.method;
  }

  get mediaMissing() {
    return this.attemptedSubmit && !!this.method && !this.mediaComplete;
  }

  get focusMissing() {
    return this.attemptedSubmit && !this.feedbackFocus;
  }

  get intentMissing() {
    return (
      this.attemptedSubmit && (this.fields.project_intent || "").trim().length === 0
    );
  }

  get tagsMissing() {
    return this.attemptedSubmit && this.tags.length === 0;
  }

  // Mirrors the backend's required-field rules so we can guide inline.
  get canSubmitClientSide() {
    return (
      this.title.trim().length > 0 &&
      !!this.method &&
      this.mediaComplete &&
      !!this.feedbackFocus &&
      this.tags.length > 0 &&
      (this.fields.project_description || "").trim().length > 0 &&
      (this.fields.self_critique || "").trim().length > 0 &&
      (this.fields.creative_direction || "").trim().length > 0 &&
      (this.fields.feedback_requested || "").trim().length > 0 &&
      (this.fields.project_intent || "").trim().length > 0
    );
  }

  get missingRequirements() {
    const missing = [];
    const add = (label, selector) => missing.push({ label, selector });

    if (this.title.trim().length === 0) {
      add(i18n("npn_submissions.form.project.title_label"), "#npn-project-title");
    }
    if (!this.method) {
      add(i18n("npn_submissions.form.project.method_label"), "#npn-project-method");
    } else if (!this.mediaComplete) {
      add(i18n("npn_submissions.form.project.media_label"), "#npn-project-media");
    }
    if ((this.fields.project_description || "").trim().length === 0) {
      add(i18n("npn_submissions.form.project.fields.project_description.label"), "#npn-field-project_description");
    }
    if (!this.feedbackFocus) {
      add(i18n("npn_submissions.form.project.focus_label"), "#npn-project-focus");
    }
    if ((this.fields.self_critique || "").trim().length === 0) {
      add(i18n("npn_submissions.form.project.fields.self_critique.label"), "#npn-field-self_critique");
    }
    if ((this.fields.creative_direction || "").trim().length === 0) {
      add(i18n("npn_submissions.form.project.fields.creative_direction.label"), "#npn-field-creative_direction");
    }
    if ((this.fields.feedback_requested || "").trim().length === 0) {
      add(i18n("npn_submissions.form.project.fields.feedback_requested.label"), "#npn-field-feedback_requested");
    }
    if ((this.fields.project_intent || "").trim().length === 0) {
      add(i18n("npn_submissions.form.project.intent_label"), "#npn-project-intent");
    }
    if (this.tags.length === 0) {
      add(i18n("npn_submissions.form.tags_label"), "#npn-project-tags");
    }
    return missing;
  }

  get showValidationSummary() {
    return this.attemptedSubmit && this.missingRequirements.length > 0;
  }

  // --- Actions: simple inputs ------------------------------------------------

  @action
  updateTitle(event) {
    this.title = event.target.value;
    this.scheduleAutosave();
  }

  @action
  selectMethod(method) {
    this.method = method;
    this.scheduleAutosave();
  }

  @action
  selectFocus(focus) {
    this.feedbackFocus = focus;
    this.scheduleAutosave();
  }

  @action
  updateField(key, event) {
    this.fields = { ...this.fields, [key]: event.target.value };
    this.scheduleAutosave();
  }

  @action
  selectIntent(value) {
    this.fields = { ...this.fields, project_intent: value };
    this.scheduleAutosave();
  }

  @action
  updateLinkUrl(event) {
    this.linkUrl = event.target.value;
    this.scheduleAutosave();
  }

  @action
  updateLinkDescription(event) {
    this.linkDescription = event.target.value;
    this.scheduleAutosave();
  }

  @action
  updateTags(tags) {
    this.tags = (tags || []).map((tag) =>
      typeof tag === "string" ? tag : (tag.name ?? tag.id)
    );
    this.scheduleAutosave();
  }

  @action
  setImages(next) {
    this.images = next;
    this.scheduleAutosave();
  }

  @action
  setAlternates(next) {
    this.alternates = next;
    this.scheduleAutosave();
  }

  // --- Uploads ---------------------------------------------------------------

  // @action so the binding survives when passed to NpnImageList as @uploadFile.
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
  async handlePdf(files) {
    const file = files[0];
    if (!file) {
      return;
    }
    const upload = await this.uploadFile(file);
    if (upload) {
      this.pdfUpload = upload;
      this.scheduleAutosave();
    }
  }

  @action
  removePdf() {
    this.pdfUpload = null;
    this.scheduleAutosave();
  }

  @action
  async handleRepresentativeImage(files) {
    const file = files[0];
    if (!file) {
      return;
    }
    const upload = await this.uploadFile(file);
    if (upload) {
      this.representativeImage = upload;
      this.scheduleAutosave();
    }
  }

  @action
  removeRepresentativeImage() {
    this.representativeImage = null;
    this.scheduleAutosave();
  }

  // --- Drafts ----------------------------------------------------------------

  @action
  loadDraft(draft) {
    this.draftId = draft.id;
    this.title = draft.title || "";

    const data = draft.data || {};
    this.method = data.method || null;
    this.feedbackFocus = data.feedback_focus || null;
    this.tags = [...(data.tags || [])];
    this.fields = { ...(data.fields || {}) };
    this.linkUrl = data.link_url || "";
    this.linkDescription = data.link_description || "";

    this.images = (draft.images || []).map((img) => ({
      upload: { id: img.id, url: img.url, original_filename: img.original_filename },
      note: img.note || "",
    }));
    this.alternates = (draft.alternates || []).map((img) => ({
      upload: { id: img.id, url: img.url, original_filename: img.original_filename },
      note: img.note || "",
    }));
    this.pdfUpload = draft.pdf
      ? {
          id: draft.pdf.id,
          url: draft.pdf.url,
          original_filename: draft.pdf.original_filename,
          human_filesize: draft.pdf.human_filesize,
        }
      : null;
    this.representativeImage = draft.representative_image
      ? {
          id: draft.representative_image.id,
          url: draft.representative_image.url,
          original_filename: draft.representative_image.original_filename,
        }
      : null;

    this.attemptedSubmit = false;

    schedule("afterRender", this, () => {
      Object.entries(this.fields).forEach(([key, value]) => {
        const el = document.getElementById(`npn-field-${key}`);
        if (el) {
          el.value = value ?? "";
        }
      });
      // The URL description is an uncontrolled textarea outside `fields`.
      const urlDesc = document.getElementById("npn-project-url-desc");
      if (urlDesc) {
        urlDesc.value = this.linkDescription ?? "";
      }
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

  // --- Payload / submit / preview --------------------------------------------

  buildPayload() {
    return {
      submission_type: "project",
      title: this.title,
      client_timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      data: {
        method: this.method,
        feedback_focus: this.feedbackFocus,
        images: this.images.map((entry) => ({
          upload_id: entry.upload.id,
          note: entry.note || "",
        })),
        alternates: this.alternates.map((entry) => ({
          upload_id: entry.upload.id,
          note: entry.note || "",
        })),
        pdf_upload_id: this.pdfUpload?.id ?? null,
        representative_image_upload_id: this.representativeImage?.id ?? null,
        link_url: this.linkUrl,
        link_description: this.linkDescription,
        tags: this.tags,
        fields: this.fields,
      },
    };
  }

  // Manual Save Draft and autosave share the same draft record via the
  // autosaver (saveNow flushes any pending autosave and saves immediately).
  @action
  saveDraft() {
    return this.autosaver.saveNow();
  }

  // --- Start New -------------------------------------------------------------

  get showStartNew() {
    return !!this.draftId || this.hasMeaningfulContent;
  }

  get startNewLabel() {
    return i18n("npn_submissions.form.drafts.start_new.project");
  }

  @action
  startNew() {
    // Confirm only when edits could be lost (pending/in-flight save or a failed
    // autosave). A fully-saved or unchanged draft resets without a prompt.
    if (this.autosaver.status === "failed" || this.autosaver.hasPendingChanges) {
      this.dialog.confirm({
        message: i18n("npn_submissions.form.drafts.start_new_confirm"),
        confirmButtonLabel: "npn_submissions.form.drafts.start_new_confirm_button",
        didConfirm: () => this.resetForm(),
      });
    } else {
      this.resetForm();
    }
  }

  // Reset to a blank Project Critique. The current draft is left saved on the
  // server (we only detach from it) and becomes resumable again; autosave stays
  // idle until there's meaningful content. Several project textareas
  // (description, feedback questions, intent details) are uncontrolled and stay
  // rendered, so clear their DOM values after the reset re-renders.
  resetForm() {
    this.autosaver.reset();
    this.draftId = null;
    this.title = "";
    this.method = null;
    this.feedbackFocus = null;
    this.images = [];
    this.alternates = [];
    this.pdfUpload = null;
    this.representativeImage = null;
    this.linkUrl = "";
    this.linkDescription = "";
    this.tags = [];
    this.fields = {};
    this.attemptedSubmit = false;

    schedule("afterRender", this, () => {
      document
        .querySelectorAll(".npn-project-form textarea")
        .forEach((el) => (el.value = ""));
    });

    this.loadDrafts();
  }

  focusFirstMissing() {
    const first = this.missingRequirements[0];
    if (first) {
      document.querySelector(first.selector)?.focus({ preventScroll: true });
    }
  }

  @action
  goToField(selector, event) {
    event?.preventDefault();
    const el = document.querySelector(selector);
    if (!el) {
      return;
    }
    el.scrollIntoView({ behavior: "smooth", block: "center" });
    const focusable = el.matches("input, textarea, button, select, [tabindex]")
      ? el
      : el.querySelector("input, textarea, button, select, [tabindex]");
    focusable?.focus({ preventScroll: true });
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
          submitDisabled: this.limitReached,
          submitDisabledReason: this.limitReached
            ? i18n("npn_submissions.form.daily_limit.short")
            : null,
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
    if (this.limitReached) {
      return false;
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
        // The draft is now submitted; stop autosaving to it.
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

  <template>
    <form class="npn-image-form npn-project-form" {{on "submit" this.submit}}>
      <header class="npn-image-form__intro">
        <h2>{{i18n "npn_submissions.form.project.intro.title"}}</h2>
        <p class="npn-image-form__lead">
          {{i18n "npn_submissions.form.project.intro.lead"}}
        </p>

        <NpnExpandableExample
          @summary={{i18n "npn_submissions.form.project.intro.guidance_summary"}}
        >
          <p>
            {{i18n "npn_submissions.form.project.intro.guidance_review_prefix"}}
            {{#if this.guidelinesUrl}}
              <a
                href={{this.guidelinesUrl}}
                target="_blank"
                rel="noopener noreferrer"
              >{{i18n "npn_submissions.form.project.intro.guidelines_link"}}</a>
            {{else}}
              {{i18n "npn_submissions.form.project.intro.guidelines_link"}}
            {{/if}}.
          </p>
          <p>{{i18n "npn_submissions.form.project.intro.guidance_definition"}}</p>
          <p>
            {{i18n "npn_submissions.form.project.intro.guidance_recommendation"}}
          </p>
          <p>
            {{i18n "npn_submissions.form.project.intro.help_prefix"}}
            {{#if this.siteSupportUrl}}
              <a
                href={{this.siteSupportUrl}}
                target="_blank"
                rel="noopener noreferrer"
              >{{i18n "npn_submissions.form.project.intro.help_support"}}</a>
            {{else}}
              {{i18n "npn_submissions.form.project.intro.help_support"}}
            {{/if}}.
          </p>
        </NpnExpandableExample>
      </header>

      {{#if this.limitReached}}
        <div class="npn-image-form__notice" aria-live="polite">
          {{i18n "npn_submissions.form.daily_limit.notice"}}
        </div>
      {{/if}}

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
                <li
                  class="npn-image-form__draft
                    {{if (eq this.draftId draft.id) 'is-active'}}"
                >
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
            @translatedLabel={{this.startNewLabel}}
            @action={{this.startNew}}
            @icon="plus"
            class="btn-default npn-image-form__start-new-button"
          />
        </div>
      {{/if}}

      <h3 class="npn-form-section">
        {{i18n "npn_submissions.form.sections.project"}}
      </h3>

      <div
        class="npn-image-form__field
          {{if this.titleMissing 'npn-image-form__field--needs-attention'}}"
      >
        <label for="npn-project-title">
          {{i18n "npn_submissions.form.project.title_label"}}
          <span class="npn-required">{{i18n "npn_submissions.form.required"}}</span>
        </label>
        <input
          id="npn-project-title"
          type="text"
          value={{this.title}}
          {{on "input" this.updateTitle}}
        />
        {{#if this.titleMissing}}
          <p class="npn-field__error" aria-live="polite">
            {{i18n "npn_submissions.form.field_required"}}
          </p>
        {{/if}}
      </div>

      <div
        class="npn-image-form__field
          {{if this.methodMissing 'npn-image-form__field--needs-attention'}}"
      >
        <label id="npn-project-method-label">
          {{i18n "npn_submissions.form.project.method_label"}}
          <span class="npn-required">{{i18n "npn_submissions.form.required"}}</span>
        </label>
        <div
          id="npn-project-method"
          class="npn-image-form__cards"
          role="group"
          aria-labelledby="npn-project-method-label"
        >
          {{#each this.methodCards as |card|}}
            <button
              type="button"
              class="npn-card {{if (eq this.method card.id) 'is-selected'}}"
              aria-pressed={{if (eq this.method card.id) 'true' 'false'}}
              {{on "click" (fn this.selectMethod card.id)}}
            >
              <span class="npn-card__title">{{card.title}}</span>
              <span class="npn-card__desc">{{card.description}}</span>
            </button>
          {{/each}}
        </div>
        {{#if this.methodMissing}}
          <p class="npn-field__error" aria-live="polite">
            {{i18n "npn_submissions.form.field_required"}}
          </p>
        {{/if}}
      </div>

      {{#if this.method}}
        <div
          id="npn-project-media"
          class="npn-image-form__field
            {{if this.mediaMissing 'npn-image-form__field--needs-attention'}}"
        >
          {{#if (eq this.method "images")}}
            <label>{{i18n "npn_submissions.form.project.media.images_label"}}</label>
            <p class="npn-help">
              {{i18n
                "npn_submissions.form.project.media.images_help"
                min=this.minImages
                max=this.maxImages
              }}
            </p>
            <NpnImageList
              @images={{this.images}}
              @onChange={{this.setImages}}
              @uploadFile={{this.uploadFile}}
              @uploading={{this.uploading}}
              @maxImages={{this.maxImages}}
              @reservedUploadIds={{this.alternateUploadIds}}
              @uploadLabel={{i18n "npn_submissions.form.upload.images"}}
              @addMoreLabel={{i18n "npn_submissions.form.upload.project_add_more"}}
              @addMoreHelp={{i18n "npn_submissions.form.upload.project_add_more_help"}}
              @enableNotes={{true}}
              @noteLabel={{i18n "npn_submissions.form.project.media.image_note_label"}}
              @notePlaceholder={{i18n "npn_submissions.form.project.media.image_note"}}
              @badge="number"
              @numberLabel={{i18n "npn_submissions.form.project.image_word"}}
            />
            {{#if this.belowRecommendedImages}}
              <p class="npn-image-form__prompt" aria-live="polite">
                {{i18n
                  "npn_submissions.form.project.media.below_recommended"
                  min=this.minImages
                  max=this.maxImages
                }}
              </p>
            {{/if}}

            <h3 class="npn-project-form__alt-heading">
              {{i18n "npn_submissions.form.project.alternates.heading"}}
            </h3>
            <p class="npn-help">
              {{i18n "npn_submissions.form.project.alternates.help"}}
            </p>
            <NpnImageList
              @images={{this.alternates}}
              @onChange={{this.setAlternates}}
              @uploadFile={{this.uploadFile}}
              @uploading={{this.uploading}}
              @maxImages={{this.maxAlternates}}
              @reservedUploadIds={{this.imageUploadIds}}
              @uploadLabel={{i18n "npn_submissions.form.project.alternates.add"}}
              @badge="number"
              @numberLabel={{i18n "npn_submissions.form.project.alternate_word"}}
            />
          {{else if (eq this.method "pdf")}}
            <label>{{i18n "npn_submissions.form.project.media.pdf_label"}}</label>
            <p class="npn-help">{{i18n "npn_submissions.form.project.media.pdf_help"}}</p>
            {{#if this.pdfUpload}}
              <div class="npn-project-form__pdf">
                <span class="npn-project-form__pdf-name">{{this.pdfFileLabel}}</span>
                <DButton
                  @icon="trash-can"
                  @action={{this.removePdf}}
                  @title="npn_submissions.form.project.media.pdf_remove"
                  @ariaLabel="npn_submissions.form.project.media.pdf_remove"
                  class="btn-flat"
                />
              </div>
            {{else}}
              <NpnUploadZone
                @accept="application/pdf,.pdf"
                @disabled={{this.uploading}}
                @label={{i18n "npn_submissions.form.project.media.pdf_add"}}
                @onFiles={{this.handlePdf}}
              />
            {{/if}}
            {{#if this.uploading}}
              <p class="npn-image-form__uploading">
                {{i18n "npn_submissions.form.uploading"}}
              </p>
            {{/if}}
          {{else if (eq this.method "url")}}
            <label for="npn-project-url">
              {{i18n "npn_submissions.form.project.media.url_label"}}
            </label>
            <input
              id="npn-project-url"
              type="url"
              value={{this.linkUrl}}
              placeholder="https://"
              {{on "input" this.updateLinkUrl}}
            />
            <label class="npn-project-form__url-desc-label">
              {{i18n "npn_submissions.form.project.media.url_desc_label"}}
            </label>
            <p class="npn-help">
              {{i18n "npn_submissions.form.project.media.url_desc_help"}}
            </p>
            <textarea
              id="npn-project-url-desc"
              {{on "input" this.updateLinkDescription}}
            ></textarea>
          {{/if}}

          {{#if this.needsRepresentativeImage}}
            <label>
              {{i18n "npn_submissions.form.project.media.rep_label"}}
              <span class="npn-required">{{i18n "npn_submissions.form.required"}}</span>
            </label>
            <p class="npn-help">
              {{i18n "npn_submissions.form.project.media.rep_help"}}
            </p>
            <p class="npn-help">
              {{i18n "npn_submissions.form.project.media.rep_help_secondary"}}
            </p>
            {{#if this.representativeImage}}
              <div class="npn-image-form__image-row">
                <div class="npn-image-form__thumb">
                  <img
                    src={{this.representativeImage.url}}
                    alt={{this.representativeImage.original_filename}}
                  />
                </div>
                <DButton
                  @icon="trash-can"
                  @action={{this.removeRepresentativeImage}}
                  @title="npn_submissions.form.images.remove"
                  @ariaLabel="npn_submissions.form.images.remove"
                  class="btn-flat"
                />
              </div>
            {{else}}
              <NpnUploadZone
                @accept="image/*"
                @disabled={{this.uploading}}
                @label={{i18n "npn_submissions.form.project.media.rep_add"}}
                @onFiles={{this.handleRepresentativeImage}}
              />
            {{/if}}
          {{/if}}

          {{#if this.mediaMissing}}
            <p class="npn-field__error" aria-live="polite">
              {{i18n "npn_submissions.form.field_required"}}
            </p>
          {{/if}}
        </div>
      {{/if}}

      <NpnField
        @fieldId={{this.descriptionField.fieldId}}
        @label={{this.descriptionField.label}}
        @help={{this.descriptionField.help}}
        @required={{this.descriptionField.required}}
        @error={{this.descriptionField.error}}
        @onInput={{fn this.updateField "project_description"}}
      />

      <h3 class="npn-form-section">
        {{i18n "npn_submissions.form.sections.critique_direction"}}
      </h3>

      <div
        class="npn-image-form__field
          {{if this.focusMissing 'npn-image-form__field--needs-attention'}}"
      >
        <label id="npn-project-focus-label">
          {{i18n "npn_submissions.form.project.focus_label"}}
          <span class="npn-required">{{i18n "npn_submissions.form.required"}}</span>
        </label>
        <div
          id="npn-project-focus"
          class="npn-image-form__cards"
          role="group"
          aria-labelledby="npn-project-focus-label"
        >
          {{#each this.focusCards as |card|}}
            <button
              type="button"
              class="npn-card {{if (eq this.feedbackFocus card.id) 'is-selected'}}"
              aria-pressed={{if (eq this.feedbackFocus card.id) 'true' 'false'}}
              {{on "click" (fn this.selectFocus card.id)}}
            >
              <span class="npn-card__title">{{card.title}}</span>
              <span class="npn-card__desc">{{card.description}}</span>
            </button>
          {{/each}}
        </div>
        {{#if this.focusMissing}}
          <p class="npn-field__error" aria-live="polite">
            {{i18n "npn_submissions.form.field_required"}}
          </p>
        {{/if}}
      </div>

      {{#each this.postFocusFields key="key" as |field|}}
        <NpnField
          @fieldId={{field.fieldId}}
          @label={{field.label}}
          @help={{field.help}}
          @required={{field.required}}
          @examples={{field.examples}}
          @error={{field.error}}
          @onInput={{fn this.updateField field.key}}
        />
      {{/each}}

      <div
        class="npn-image-form__field
          {{if this.intentMissing 'npn-image-form__field--needs-attention'}}"
      >
        <label>
          {{i18n "npn_submissions.form.project.intent_label"}}
          <span class="npn-required">{{i18n "npn_submissions.form.required"}}</span>
        </label>
        <div id="npn-project-intent">
          <ComboBox
            @value={{this.intentValue}}
            @content={{this.intentOptions}}
            @onChange={{this.selectIntent}}
            @options={{hash none="npn_submissions.form.project.intent_placeholder"}}
          />
        </div>
        {{#if this.intentMissing}}
          <p class="npn-field__error" aria-live="polite">
            {{i18n "npn_submissions.form.field_required"}}
          </p>
        {{/if}}
      </div>

      <div class="npn-image-form__field">
        <label for="npn-field-project_intent_details">
          {{i18n "npn_submissions.form.project.intent_details_label"}}
        </label>
        <p class="npn-help">
          {{i18n "npn_submissions.form.project.intent_details_help"}}
        </p>
        <textarea
          id="npn-field-project_intent_details"
          {{on "input" (fn this.updateField "project_intent_details")}}
        ></textarea>
      </div>

      <h3 class="npn-form-section">
        {{i18n "npn_submissions.form.sections.review"}}
      </h3>

      <div
        class="npn-image-form__field
          {{if this.tagsMissing 'npn-image-form__field--needs-attention'}}"
      >
        <label>
          {{i18n "npn_submissions.form.tags_label"}}
          <span class="npn-required">{{i18n "npn_submissions.form.required"}}</span>
        </label>
        <div id="npn-project-tags">
          {{#if this.tagsConstrained}}
            <MultiSelect
              @value={{this.tags}}
              @content={{this.allowedTagContent}}
              @onChange={{this.updateTags}}
              @options={{hash filterable=true}}
            />
          {{else}}
            <TagChooser
              @tags={{this.tags}}
              @onChange={{this.updateTags}}
              @options={{hash allowAny=false}}
            />
          {{/if}}
        </div>
        {{#if this.tagsMissing}}
          <p class="npn-field__error" aria-live="polite">
            {{i18n "npn_submissions.form.field_required"}}
          </p>
        {{/if}}
      </div>

      {{#if this.showValidationSummary}}
        <div class="npn-image-form__validation" aria-live="assertive">
          <p>{{i18n "npn_submissions.form.validation.heading"}}</p>
          <ul>
            {{#each this.missingRequirements as |req|}}
              <li>
                <button
                  type="button"
                  class="npn-image-form__validation-link"
                  {{on "click" (fn this.goToField req.selector)}}
                >{{req.label}}</button>
              </li>
            {{/each}}
          </ul>
        </div>
      {{/if}}

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
          @label="npn_submissions.form.project.submit"
          @action={{this.submit}}
          @disabled={{this.submitDisabled}}
          @isLoading={{this.submitting}}
          class="btn-primary"
        />
      </div>

      <NpnAutosaveStatus @autosaver={{this.autosaver}} />

      {{#if this.limitReached}}
        <p class="npn-image-form__notice-inline">
          {{i18n "npn_submissions.form.daily_limit.short"}}
        </p>
      {{/if}}
    </form>
  </template>
}
