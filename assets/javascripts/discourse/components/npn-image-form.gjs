import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn, hash } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { schedule } from "@ember/runloop";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import MultiSelect from "discourse/select-kit/components/multi-select";
import TagChooser from "discourse/select-kit/components/tag-chooser";
import { eq } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import NpnDraftAutosaver from "../lib/npn-draft-autosaver";
import { extractPhotoMetadata } from "../lib/npn-exif";
import NpnAutosaveStatus from "./npn-autosave-status";
import NpnExpandableExample from "./npn-expandable-example";
import NpnField from "./npn-field";
import NpnImageList from "./npn-image-list";
import NpnPreviewModal from "./npn-preview-modal";
import NpnWeeklyChallengePanel from "./npn-weekly-challenge-panel";

const STYLES = ["standard", "in_depth", "reaction"];
const FOCUSES = ["artistic", "technical", "both"];

// Per-focus guidance for the feedback-request fields. The keys map to i18n
// entries under form.examples.feedback.<focus>.items.* and form.chips.<focus>.*
const FOCUS_EXAMPLE_KEYS = {
  artistic: ["composition", "eye", "processing", "distractions", "communicate", "mood"],
  technical: ["sharpness", "dof", "shutter", "exposure", "artifacts", "technique"],
  both: ["composition", "processing", "distractions", "sharpness", "dof", "issues"],
};

const FOCUS_CHIP_KEYS = {
  artistic: ["composition", "mood", "color", "processing", "story", "distractions"],
  technical: ["sharpness", "dof", "exposure", "focus", "artifacts", "color", "print"],
  both: ["composition", "mood", "processing", "distractions", "sharpness", "dof", "exposure", "technical_quality"],
};

export default class NpnImageForm extends Component {
  @service router;
  @service siteSettings;
  @service modal;
  @service dialog;

  @tracked title = "";
  @tracked selectedStyle = null;
  @tracked selectedFocus = null;
  // Ordered list of { upload, note }. The first entry is the main image.
  // Editing (upload, reorder, notes) is handled by NpnImageList.
  @tracked images = [];
  // Optional EXIF/metadata screenshot tied to Technical Details.
  @tracked metadataScreenshot = null;
  // Formatted, safe EXIF read client-side from the main image (or null). Used to
  // offer an opt-in "Use photo metadata" button; never auto-inserted.
  @tracked photoMetadata = null;
  // True once we've attempted EXIF extraction on a main image, so we can show a
  // calm "no metadata found" hint only after an image exists (not before upload).
  @tracked photoMetadataChecked = false;
  // True once the user has inserted the photo metadata, so the helper switches to
  // an "added" state (instead of disappearing, which would make the UI jump).
  @tracked photoMetadataUsed = false;
  @tracked tags = [];
  // When a descriptive tag group is configured, selection is limited to its
  // tags (loaded on init); otherwise the normal tag chooser is used.
  @tracked tagsConstrained = false;
  @tracked allowedTags = [];
  @tracked fields = {};
  @tracked draftId = null;
  // "image" or "weekly_challenge". A context flag, not a separate form: weekly
  // challenge reuses this whole component and only differs by intro copy, the
  // weekly panel, and the auto-applied weekly tag (added server-side). Set from
  // @submissionType, and re-derived from a draft when one is loaded.
  @tracked submissionType;
  // The user's saved drafts for this submission type, so they can resume one.
  @tracked drafts = [];
  @tracked uploading = false;
  @tracked submitting = false;
  @tracked previewing = false;
  // True when the user has already used their daily critique submission. Drafts
  // and preview stay available; only the final submit is blocked.
  @tracked limitReached = false;
  // Set once the user attempts to submit, so guidance prompts escalate from
  // "neither selected, stay quiet" to "you need to choose these".
  @tracked attemptedSubmit = false;

  constructor() {
    super(...arguments);
    this.submissionType = this.args.submissionType ?? "image";
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
      this.images.length > 0 ||
      this.tags.length > 0 ||
      !!this.selectedStyle ||
      !!this.selectedFocus ||
      !!this.metadataScreenshot ||
      Object.values(this.fields).some((v) => (v || "").trim().length > 0)
    );
  }

  scheduleAutosave() {
    this.autosaver.schedule();
  }

  // If admins constrained descriptive tags to a tag group, fetch the allowed
  // tags so the chooser only offers those. Non-blocking: on failure we fall
  // back to the normal tag chooser.
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

  // select-kit MultiSelect content (id == name so selected values are tag names).
  get allowedTagContent() {
    return this.allowedTags.map((name) => ({ id: name, name }));
  }

  get isWeeklyChallenge() {
    return this.submissionType === "weekly_challenge";
  }

  // Intro copy varies by entry point; everything else is shared.
  get introTitle() {
    return i18n(`npn_submissions.form.intro.${this.submissionType}.title`);
  }

  get introLead() {
    return i18n(`npn_submissions.form.intro.${this.submissionType}.lead`);
  }

  // Drafts the user could resume — excludes the one they're actively editing, so
  // the panel doesn't pop in (and jump the layout) when autosave creates it.
  get resumableDrafts() {
    return this.drafts.filter((draft) => draft.id !== this.draftId);
  }

  get hasDrafts() {
    return this.resumableDrafts.length > 0;
  }

  // Fetch the user's saved image drafts so they can resume one. Each draft gets
  // a display label (the image title, or a dated fallback when untitled).
  async loadDrafts() {
    try {
      const result = await ajax("/npn-submissions/drafts");
      this.drafts = (result.drafts || [])
        .filter((draft) => draft.submission_type === this.submissionType)
        .map((draft) => ({ ...draft, label: this.draftLabel(draft) }));
    } catch {
      // A failed draft fetch should never block submitting; just show nothing.
      this.drafts = [];
    }
  }

  // Check the daily limit (browser-timezone aware) when the form opens, so we
  // can warn before the user fills everything in. Failure is non-blocking.
  async loadDailyLimit() {
    try {
      const tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
      const result = await ajax("/npn-submissions/daily-limit", {
        data: { tz },
      });
      this.limitReached = !!result.limit_reached;
    } catch {
      this.limitReached = false;
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

  // Rehydrate the whole form from a saved draft. Subsequent saves update it.
  @action
  loadDraft(draft) {
    this.draftId = draft.id;
    // Reopen in the draft's own mode (e.g. a Weekly Challenge draft restores
    // weekly mode so the weekly tag is applied on submit).
    this.submissionType = draft.submission_type || this.submissionType;
    this.title = draft.title || "";
    this.selectedStyle = draft.critique_style || null;

    const data = draft.data || {};
    this.selectedFocus = data.feedback_focus || null;
    this.tags = [...(data.tags || [])];
    this.fields = { ...(data.fields || {}) };

    this.images = (draft.images || []).map((img) => ({
      upload: {
        id: img.id,
        url: img.url,
        original_filename: img.original_filename,
      },
      note: img.note || "",
    }));

    this.metadataScreenshot = draft.metadata_screenshot
      ? {
          id: draft.metadata_screenshot.id,
          url: draft.metadata_screenshot.url,
          original_filename: draft.metadata_screenshot.original_filename,
        }
      : null;

    // A resumed draft only has the stored (EXIF-stripped) upload, not the
    // original file, so there's no photo metadata to offer.
    this.photoMetadata = null;
    this.photoMetadataChecked = false;
    this.photoMetadataUsed = false;

    this.attemptedSubmit = false;

    // The question textareas are uncontrolled (NpnField), so set their values
    // directly once the style-driven fields have rendered.
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

  get styleCards() {
    return STYLES.map((id) => ({
      id,
      title: i18n(`npn_submissions.form.styles.${id}.title`),
      description: i18n(`npn_submissions.form.styles.${id}.description`),
    }));
  }

  get focusCards() {
    return FOCUSES.map((id) => ({
      id,
      title: i18n(`npn_submissions.form.focuses.${id}.title`),
      description: i18n(`npn_submissions.form.focuses.${id}.description`),
    }));
  }

  // Examples shown under feedback-request fields, tailored to the selected
  // feedback focus. Returns a neutral prompt until a focus is chosen.
  get feedbackExampleProps() {
    const focus = this.selectedFocus;
    if (!focus) {
      return { neutral: i18n("npn_submissions.form.examples.feedback.neutral") };
    }
    return {
      summary: i18n(`npn_submissions.form.examples.feedback.${focus}.summary`),
      items: (FOCUS_EXAMPLE_KEYS[focus] || []).map((key) =>
        i18n(`npn_submissions.form.examples.feedback.${focus}.items.${key}`)
      ),
    };
  }

  // Prompt chips for feedback-request fields, tailored to the selected focus.
  // Null until a focus is chosen, so no chips appear.
  get focusChips() {
    const focus = this.selectedFocus;
    if (!focus) {
      return null;
    }
    return (FOCUS_CHIP_KEYS[focus] || []).map((key) => ({
      label: i18n(`npn_submissions.form.chips.${focus}.${key}.label`),
      text: i18n(`npn_submissions.form.chips.${focus}.${key}.text`),
    }));
  }

  get critiqueGuideUrl() {
    return this.siteSettings.npn_submissions_critique_guide_url;
  }

  get siteSupportUrl() {
    return this.siteSettings.npn_submissions_site_support_url;
  }

  get hasHelpLinks() {
    return !!this.critiqueGuideUrl || !!this.siteSupportUrl;
  }

  get exportGuideUrl() {
    return this.siteSettings.npn_submissions_export_guide_url;
  }

  get downsampleThreshold() {
    return (
      parseInt(this.siteSettings.npn_submissions_downsample_threshold_mb, 10) || 3
    );
  }

  get maxImages() {
    return parseInt(this.siteSettings.npn_submissions_max_single_images, 10) || 1;
  }

  // Per-image notes and the "Main" badge only make sense once there's more than
  // one image; with a single image they're noise.
  get hasMultipleImages() {
    return this.images.length > 1;
  }

  // `adaptive: true` marks a feedback-request field that should show the
  // focus-tailored examples and prompt chips.
  def(
    key,
    { labelKey, helpKey = null, required = false, adaptive = false, optional = false }
  ) {
    const missing =
      required &&
      this.attemptedSubmit &&
      (this.fields[key] || "").trim().length === 0;
    return {
      key,
      fieldId: `npn-field-${key}`,
      label: i18n(`npn_submissions.form.fields.${labelKey}.label`),
      help: helpKey ? i18n(`npn_submissions.form.fields.${helpKey}.help`) : null,
      required,
      // Subtle "(optional)" hint for fields we deliberately mark as optional.
      optional,
      examples: adaptive ? this.feedbackExampleProps : null,
      chips: adaptive ? this.focusChips : null,
      // Mirror the project form's field(): surface an inline required error after
      // a submit attempt. The backend enforces these per-style required fields.
      error: missing ? i18n("npn_submissions.form.field_required") : null,
    };
  }

  get technicalField() {
    const focus = this.selectedFocus;
    // Until a feedback focus is chosen, the required/optional state is not yet
    // finalized — render neutral "pending" help and no required marker.
    let variant = "help_pending";
    if (focus === "technical") {
      variant = "help_technical";
    } else if (focus === "both") {
      variant = "help_both";
    } else if (focus === "artistic") {
      variant = "help_artistic";
    }
    return {
      key: "technical_details",
      fieldId: "npn-field-technical_details",
      label: i18n("npn_submissions.form.fields.technical_details.label"),
      help: i18n(`npn_submissions.form.fields.technical_details.${variant}`),
      required: this.technicalRequired,
      // Mark "(optional)" only once a non-technical focus is chosen; while the
      // focus is still pending the field shows neutral "pending" help instead.
      optional: !!focus && !this.technicalRequired,
      examples: null,
      chips: null,
      withMetadata: true,
      error: this.technicalMissing
        ? i18n("npn_submissions.form.fields.technical_details.required_error")
        : null,
    };
  }

  // Standard and In-Depth render their fields followed by Technical Details.
  get standardFields() {
    let fields;
    if (this.selectedStyle === "standard") {
      fields = [
        this.def("about_this_image", {
          labelKey: "about_this_image",
          helpKey: "about_this_image",
          optional: true,
        }),
        this.def("feedback_requested", {
          labelKey: "feedback_requested_standard",
          helpKey: "feedback_requested_standard",
          required: true,
          adaptive: true,
        }),
      ];
    } else if (this.selectedStyle === "in_depth") {
      fields = [
        this.def("self_critique", { labelKey: "self_critique", required: true }),
        this.def("creative_direction", {
          labelKey: "creative_direction",
          helpKey: "creative_direction",
          required: true,
        }),
        this.def("feedback_requested", {
          labelKey: "feedback_requested_in_depth",
          helpKey: "feedback_requested_in_depth",
          required: true,
          adaptive: true,
        }),
        this.def("about_this_image", {
          labelKey: "about_this_image",
          helpKey: "about_this_image",
          optional: true,
        }),
      ];
    } else {
      return [];
    }
    return [...fields, this.technicalField];
  }

  get reactionQuestionsField() {
    return this.def("questions_for_viewers", {
      labelKey: "questions_for_viewers",
      helpKey: "questions_for_viewers",
      required: true,
      adaptive: true,
    });
  }

  get reactionHiddenFields() {
    return [
      this.def("about_this_image", {
        labelKey: "about_this_image",
        helpKey: "about_this_image",
        optional: true,
      }),
      this.technicalField,
      this.def("feedback_after", { labelKey: "feedback_after" }),
    ];
  }

  get busy() {
    return (
      this.uploading ||
      this.autosaver.isSaving ||
      this.submitting ||
      this.previewing
    );
  }

  // Save Draft and Preview stay enabled when the daily limit is reached; only
  // the final submit is blocked.
  get submitDisabled() {
    return this.busy || this.limitReached;
  }

  // Critique style drives which question fields appear. Prompt to choose it
  // once the user has engaged elsewhere (picked a focus) or tried to submit.
  get showStylePrompt() {
    return !this.selectedStyle && (!!this.selectedFocus || this.attemptedSubmit);
  }

  // Feedback focus drives whether Technical Details is required. Prompt to
  // choose it once a style is picked or the user tries to submit.
  get showFocusPrompt() {
    return !this.selectedFocus && (!!this.selectedStyle || this.attemptedSubmit);
  }

  get technicalRequired() {
    return this.selectedFocus === "technical";
  }

  // Technical details are satisfied by either typed text or a metadata
  // screenshot. Mirrors the backend's "text OR screenshot" rule.
  get hasTechnicalContent() {
    return !!(this.fields.technical_details || "").trim() || !!this.metadataScreenshot;
  }

  get technicalMissing() {
    return (
      this.attemptedSubmit && this.technicalRequired && !this.hasTechnicalContent
    );
  }

  get imagesMissing() {
    return this.attemptedSubmit && this.images.length === 0;
  }

  get titleMissing() {
    return this.attemptedSubmit && this.title.trim().length === 0;
  }

  get tagsMissing() {
    return this.attemptedSubmit && this.tags.length === 0;
  }

  // Mirrors the backend's required-field rules so we can guide inline instead of
  // waiting for a submit-time server error. The backend remains the source of
  // truth and re-checks everything (plus per-style required fields).
  // Per-style question fields (excluding Technical Details, which has its own
  // required/optional logic). Lets the client mirror the backend's per-style
  // required-field rules instead of only catching them at submit time.
  get questionFields() {
    const fields =
      this.selectedStyle === "reaction"
        ? [this.reactionQuestionsField, ...this.reactionHiddenFields]
        : this.standardFields;
    return fields.filter((field) => field.key !== "technical_details");
  }

  get canSubmitClientSide() {
    if (this.images.length === 0) {
      return false;
    }
    if (this.title.trim().length === 0) {
      return false;
    }
    if (this.tags.length === 0) {
      return false;
    }
    if (!this.selectedStyle || !this.selectedFocus) {
      return false;
    }
    if (
      this.questionFields.some(
        (field) =>
          field.required && (this.fields[field.key] || "").trim().length === 0
      )
    ) {
      return false;
    }
    if (this.technicalRequired && !this.hasTechnicalContent) {
      return false;
    }
    return true;
  }

  // Human-readable list of required fields still missing, mirroring
  // canSubmitClientSide. Surfaced near the submit button so the user isn't left
  // hunting for a highlighted field that may be scrolled off-screen.
  get missingRequirements() {
    const missing = [];
    if (this.images.length === 0) {
      missing.push({
        label: i18n("npn_submissions.form.images.label"),
        selector: "#npn-images-field",
      });
    }
    if (this.title.trim().length === 0) {
      missing.push({
        label: i18n("npn_submissions.form.title_label"),
        selector: "#npn-title",
      });
    }
    if (this.tags.length === 0) {
      missing.push({
        label: i18n("npn_submissions.form.tags_label"),
        selector: "#npn-tags-field",
      });
    }
    if (!this.selectedStyle) {
      missing.push({
        label: i18n("npn_submissions.form.style_label"),
        selector: "#npn-style-cards",
      });
    }
    if (!this.selectedFocus) {
      missing.push({
        label: i18n("npn_submissions.form.focus_label"),
        selector: "#npn-focus-cards",
      });
    }
    this.questionFields.forEach((field) => {
      if (field.required && (this.fields[field.key] || "").trim().length === 0) {
        missing.push({ label: field.label, selector: `#${field.fieldId}` });
      }
    });
    if (this.technicalRequired && !this.hasTechnicalContent) {
      missing.push({
        label: i18n("npn_submissions.form.fields.technical_details.label"),
        selector: "#npn-field-technical_details",
      });
    }
    return missing;
  }

  get showValidationSummary() {
    return this.attemptedSubmit && this.missingRequirements.length > 0;
  }

  @action
  updateTitle(event) {
    this.title = event.target.value;
    this.scheduleAutosave();
  }

  @action
  selectStyle(style) {
    this.selectedStyle = style;
    this.scheduleAutosave();
  }

  @action
  selectFocus(focus) {
    this.selectedFocus = focus;
    this.scheduleAutosave();
  }

  @action
  updateTags(tags) {
    this.tags = (tags || []).map((tag) => (typeof tag === "string" ? tag : (tag.name ?? tag.id)));
    this.scheduleAutosave();
  }

  @action
  updateField(key, event) {
    this.fields = { ...this.fields, [key]: event.target.value };
    this.scheduleAutosave();
  }

  @action
  appendChip(fieldId, key, text) {
    const current = this.fields[key] || "";
    const next = current ? `${current}\n${text}` : text;
    this.fields = { ...this.fields, [key]: next };
    const el = document.getElementById(fieldId);
    if (el) {
      el.value = next;
      el.focus();
    }
    this.scheduleAutosave();
  }

  // Insert an optional Technical Details template. Never overwrites: an empty
  // field gets the template as-is; otherwise it's appended after a blank line.
  @action
  appendTemplate(fieldId, key, text) {
    const current = this.fields[key] || "";
    const next =
      current.trim().length === 0
        ? text
        : `${current.replace(/\s+$/, "")}\n\n${text}`;
    this.fields = { ...this.fields, [key]: next };
    const el = document.getElementById(fieldId);
    if (el) {
      el.value = next;
      el.focus();
    }
    this.scheduleAutosave();
  }

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

  // Images are edited (upload/reorder/notes) by NpnImageList, which hands back
  // the new ordered array here.
  @action
  setImages(next) {
    this.images = next;
    // If the photo is removed, drop any metadata read from it.
    if (next.length === 0) {
      this.photoMetadata = null;
      this.photoMetadataChecked = false;
      this.photoMetadataUsed = false;
    }
    this.scheduleAutosave();
  }

  // Called by NpnImageList when the main (first) image is added. Read safe EXIF
  // from the original file in the browser and stash the formatted text so we can
  // offer an opt-in "Use photo metadata" button. Fire-and-forget and fully
  // defensive: it never throws and never blocks upload/draft/preview/submit.
  @action
  async captureMainImageMetadata(file) {
    const metadata = await extractPhotoMetadata(file);
    this.photoMetadata = metadata || null;
    this.photoMetadataChecked = true;
    // Fresh metadata hasn't been inserted yet.
    this.photoMetadataUsed = false;
  }

  // Insert the extracted photo metadata into Technical Details (append after a
  // blank line / never overwrite, via appendTemplate), and flip the helper to
  // its "added" state so the box stays put instead of disappearing.
  @action
  usePhotoMetadata(fieldId, key, text) {
    this.appendTemplate(fieldId, key, text);
    this.photoMetadataUsed = true;
  }

  @action
  async addMetadataFile(files) {
    const file = files[0];
    if (!file) {
      return;
    }
    const upload = await this.uploadFile(file);
    if (upload) {
      this.metadataScreenshot = upload;
      this.scheduleAutosave();
    }
  }

  @action
  removeMetadataScreenshot() {
    this.metadataScreenshot = null;
    this.scheduleAutosave();
  }

  buildPayload() {
    return {
      submission_type: this.submissionType,
      critique_style: this.selectedStyle,
      title: this.title,
      client_timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      data: {
        feedback_focus: this.selectedFocus,
        images: this.images.map((entry) => ({
          upload_id: entry.upload.id,
          note: entry.note || "",
        })),
        metadata_screenshot_upload_id: this.metadataScreenshot?.id ?? null,
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

  // Offer "Start New" once there's an active draft or meaningful content to
  // clear; a pristine blank form has nothing to reset.
  get showStartNew() {
    return !!this.draftId || this.hasMeaningfulContent;
  }

  // Label adapts to the current submission type (image vs weekly challenge).
  get startNewLabel() {
    return i18n(`npn_submissions.form.drafts.start_new.${this.submissionType}`);
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

  // Reset to a blank submission of the SAME type. The current draft is left
  // saved on the server (we only detach from it) and becomes resumable again;
  // autosave stays idle until the new submission has meaningful content. The
  // question textareas are removed from the DOM when the style clears, so no
  // manual textarea clearing is needed here.
  resetForm() {
    this.autosaver.reset();
    this.draftId = null;
    this.title = "";
    this.images = [];
    this.metadataScreenshot = null;
    this.photoMetadata = null;
    this.photoMetadataChecked = false;
    this.photoMetadataUsed = false;
    this.tags = [];
    this.selectedStyle = null;
    this.selectedFocus = null;
    this.fields = {};
    this.attemptedSubmit = false;
    this.loadDrafts();
  }

  focusFirstMissing() {
    let selector;
    if (this.images.length === 0) {
      selector = ".npn-upload-zone input";
    } else if (this.title.trim().length === 0) {
      selector = "#npn-title";
    } else if (this.tags.length === 0) {
      selector = "#npn-tags-field .select-kit-header";
    } else if (!this.selectedStyle) {
      selector = "#npn-style-cards .npn-card";
    } else if (!this.selectedFocus) {
      selector = "#npn-focus-cards .npn-card";
    } else if (this.technicalMissing) {
      selector = "#npn-field-technical_details";
    }
    if (selector) {
      // Move focus for accessibility, but don't scroll the viewport away from
      // the buttons — the validation summary by the submit button already says
      // what's missing.
      document.querySelector(selector)?.focus({ preventScroll: true });
    }
  }

  // Jump to a still-missing field from the validation summary: scroll it into
  // view and move focus to its first interactive control.
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

    // The backend re-validates, but gate here so an incomplete form gets the
    // same inline guidance as Submit rather than a preview error dialog.
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
          // The title becomes the topic title, shown above the post on the topic
          // page; surface it here so the preview matches.
          title: this.title,
          cooked: result.cooked,
          markdown: result.markdown,
          // Tags that will be applied (includes the auto weekly tag), shown as
          // preview metadata outside the post body.
          tags: result.tags,
          // Mirror the form's daily-limit state so the modal's submit matches.
          submitDisabled: this.limitReached,
          submitDisabledReason: this.limitReached
            ? i18n("npn_submissions.form.daily_limit.short")
            : null,
          // Submit from the modal runs the normal submit path; the modal closes
          // on the resulting route transition.
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
    // Hard stop in case the disabled button is bypassed; the backend enforces
    // this too, but this avoids a pointless round-trip and error dialog.
    if (this.limitReached) {
      return false;
    }
    this.attemptedSubmit = true;

    // Surface the inline prompts (now visible) and stop before the round-trip.
    // The backend still validates everything on the real submit below.
    if (!this.canSubmitClientSide) {
      this.focusFirstMissing();
      return;
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
    <form class="npn-image-form" {{on "submit" this.submit}}>
      <header class="npn-image-form__intro">
        <h2>{{this.introTitle}}</h2>
        <p class="npn-image-form__lead">
          {{this.introLead}}
        </p>

        <NpnExpandableExample
          @summary={{i18n "npn_submissions.form.intro.help_summary"}}
        >
          <p>{{i18n "npn_submissions.form.intro.exchange"}}</p>
          <p>{{i18n "npn_submissions.form.intro.daily_limit"}}</p>
          {{#if this.hasHelpLinks}}
            <p class="npn-image-form__help-links">
              <span>{{i18n "npn_submissions.form.intro.help_prefix"}}</span>
              {{#if this.siteSupportUrl}}
                <a href={{this.siteSupportUrl}}>
                  {{i18n "npn_submissions.form.intro.help_support"}}
                </a>
              {{/if}}
              {{#if this.critiqueGuideUrl}}
                <a href={{this.critiqueGuideUrl}}>
                  {{i18n "npn_submissions.form.intro.help_guide"}}
                </a>
              {{/if}}
            </p>
          {{/if}}
        </NpnExpandableExample>
      </header>

      {{#if this.isWeeklyChallenge}}
        <NpnWeeklyChallengePanel />
      {{/if}}

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
        {{i18n "npn_submissions.form.sections.image"}}
      </h3>

      <div
        id="npn-images-field"
        class="npn-image-form__field
          {{if this.imagesMissing 'npn-image-form__field--needs-attention'}}"
      >
        <label>
          {{i18n "npn_submissions.form.images.label"}}
          <span class="npn-required">{{i18n "npn_submissions.form.required"}}</span>
        </label>
        <p class="npn-help">{{i18n "npn_submissions.form.images.help"}}</p>

        <NpnImageList
          @images={{this.images}}
          @onChange={{this.setImages}}
          @uploadFile={{this.uploadFile}}
          @uploading={{this.uploading}}
          @maxImages={{this.maxImages}}
          @uploadLabel={{i18n "npn_submissions.form.upload.images"}}
          @addMoreLabel={{i18n "npn_submissions.form.upload.images_add_more"}}
          @addMoreHelp={{i18n "npn_submissions.form.upload.images_add_more_help"}}
          @enableNotes={{this.hasMultipleImages}}
          @notePlaceholder={{i18n "npn_submissions.form.images.note_placeholder"}}
          @badge="main"
          @mainBadgeText={{i18n "npn_submissions.form.images.main_badge"}}
          @singleLarge={{true}}
          @onPrimaryFile={{this.captureMainImageMetadata}}
        />

        {{#if this.imagesMissing}}
          <p class="npn-image-form__prompt" aria-live="polite">
            {{i18n "npn_submissions.form.prompts.add_image"}}
          </p>
        {{/if}}

        <NpnExpandableExample
          @summary={{i18n "npn_submissions.form.specs.summary"}}
        >
          <ul class="npn-image-form__specs">
            <li>{{i18n "npn_submissions.form.specs.format"}}</li>
            <li>{{i18n "npn_submissions.form.specs.dimensions"}}</li>
            <li>
              {{i18n
                "npn_submissions.form.specs.file_size"
                threshold=this.downsampleThreshold
              }}
            </li>
            <li>{{i18n "npn_submissions.form.specs.quality"}}</li>
            <li>{{i18n "npn_submissions.form.specs.best_practice"}}</li>
            {{#if this.exportGuideUrl}}
              <li>
                {{i18n "npn_submissions.form.specs.learn_more_prefix"}}
                <a
                  href={{this.exportGuideUrl}}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  {{i18n "npn_submissions.form.specs.learn_more_link"}}
                </a>
              </li>
            {{/if}}
          </ul>
        </NpnExpandableExample>
      </div>

      <div
        class="npn-image-form__field
          {{if this.titleMissing 'npn-image-form__field--needs-attention'}}"
      >
        <label for="npn-title">
          {{i18n "npn_submissions.form.title_label"}}
          <span class="npn-required">{{i18n "npn_submissions.form.required"}}</span>
        </label>
        <input
          id="npn-title"
          type="text"
          value={{this.title}}
          {{on "input" this.updateTitle}}
        />
        {{#if this.titleMissing}}
          <p class="npn-image-form__prompt" aria-live="polite">
            {{i18n "npn_submissions.form.prompts.enter_title"}}
          </p>
        {{/if}}
      </div>

      <div
        id="npn-tags-field"
        class="npn-image-form__field
          {{if this.tagsMissing 'npn-image-form__field--needs-attention'}}"
      >
        <label>
          {{i18n "npn_submissions.form.tags_label"}}
          <span class="npn-required">{{i18n "npn_submissions.form.required"}}</span>
        </label>
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
        {{#if this.tagsMissing}}
          <p class="npn-image-form__prompt" aria-live="polite">
            {{i18n "npn_submissions.form.prompts.add_tags"}}
          </p>
        {{/if}}
      </div>

      <h3 class="npn-form-section">
        {{i18n "npn_submissions.form.sections.critique_direction"}}
      </h3>

      <div
        class="npn-image-form__field
          {{if this.showStylePrompt 'npn-image-form__field--needs-attention'}}"
      >
        <label id="npn-style-label">{{i18n
            "npn_submissions.form.style_label"
          }}</label>
        <div
          id="npn-style-cards"
          class="npn-image-form__cards"
          role="group"
          aria-labelledby="npn-style-label"
        >
          {{#each this.styleCards as |card|}}
            <button
              type="button"
              class="npn-card {{if (eq this.selectedStyle card.id) 'is-selected'}}"
              aria-pressed={{if (eq this.selectedStyle card.id) 'true' 'false'}}
              {{on "click" (fn this.selectStyle card.id)}}
            >
              <span class="npn-card__title">{{card.title}}</span>
              <span class="npn-card__desc">{{card.description}}</span>
            </button>
          {{/each}}
        </div>
        {{#if this.showStylePrompt}}
          <p class="npn-image-form__prompt" aria-live="polite">
            {{i18n "npn_submissions.form.prompts.choose_style"}}
          </p>
        {{/if}}
      </div>

      <div
        class="npn-image-form__field
          {{if this.showFocusPrompt 'npn-image-form__field--needs-attention'}}"
      >
        <label id="npn-focus-label">{{i18n
            "npn_submissions.form.focus_label"
          }}</label>
        <div
          id="npn-focus-cards"
          class="npn-image-form__cards"
          role="group"
          aria-labelledby="npn-focus-label"
        >
          {{#each this.focusCards as |card|}}
            <button
              type="button"
              class="npn-card {{if (eq this.selectedFocus card.id) 'is-selected'}}"
              aria-pressed={{if (eq this.selectedFocus card.id) 'true' 'false'}}
              {{on "click" (fn this.selectFocus card.id)}}
            >
              <span class="npn-card__title">{{card.title}}</span>
              <span class="npn-card__desc">{{card.description}}</span>
            </button>
          {{/each}}
        </div>
        {{#if this.showFocusPrompt}}
          <p class="npn-image-form__prompt" aria-live="polite">
            {{i18n "npn_submissions.form.prompts.choose_focus"}}
          </p>
        {{/if}}
      </div>

      {{#if this.selectedStyle}}
        <h3 class="npn-form-section">
          {{i18n "npn_submissions.form.sections.questions"}}
        </h3>

        {{! Single hint at the top of the freeform-fields section so the
        Markdown/@mention reminder isn't repeated under every textarea. }}
        <p class="npn-field__hint">
          {{i18n "npn_submissions.form.markdown_supported"}}
        </p>

        {{#if (eq this.selectedStyle "reaction")}}
          {{#let this.reactionQuestionsField as |field|}}
            <NpnField
              @fieldId={{field.fieldId}}
              @label={{field.label}}
              @help={{field.help}}
              @required={{field.required}}
              @optional={{field.optional}}
              @examples={{field.examples}}
              @chips={{field.chips}}
              @error={{field.error}}
              @withMetadata={{field.withMetadata}}
              @metadataUpload={{this.metadataScreenshot}}
              @metadataUploading={{this.uploading}}
              @onMetadataFiles={{this.addMetadataFile}}
              @onRemoveMetadata={{this.removeMetadataScreenshot}}
              @photoMetadataChecked={{this.photoMetadataChecked}}
              @onInput={{fn this.updateField field.key}}
              @onChip={{fn this.appendChip field.fieldId field.key}}
              @onTemplate={{fn this.appendTemplate field.fieldId field.key}}
              @photoMetadata={{this.photoMetadata}}
              @photoMetadataUsed={{this.photoMetadataUsed}}
              @onUsePhotoMetadata={{fn this.usePhotoMetadata field.fieldId field.key}}
            />
          {{/let}}

          <h3>{{i18n "npn_submissions.form.hidden_notes.label"}}</h3>
          <p class="npn-help">{{i18n "npn_submissions.form.hidden_notes.help"}}</p>

          {{#each this.reactionHiddenFields key="key" as |field|}}
            <NpnField
              @fieldId={{field.fieldId}}
              @label={{field.label}}
              @help={{field.help}}
              @required={{field.required}}
              @optional={{field.optional}}
              @examples={{field.examples}}
              @chips={{field.chips}}
              @error={{field.error}}
              @withMetadata={{field.withMetadata}}
              @metadataUpload={{this.metadataScreenshot}}
              @metadataUploading={{this.uploading}}
              @onMetadataFiles={{this.addMetadataFile}}
              @onRemoveMetadata={{this.removeMetadataScreenshot}}
              @photoMetadataChecked={{this.photoMetadataChecked}}
              @onInput={{fn this.updateField field.key}}
              @onChip={{fn this.appendChip field.fieldId field.key}}
              @onTemplate={{fn this.appendTemplate field.fieldId field.key}}
              @photoMetadata={{this.photoMetadata}}
              @photoMetadataUsed={{this.photoMetadataUsed}}
              @onUsePhotoMetadata={{fn this.usePhotoMetadata field.fieldId field.key}}
            />
          {{/each}}
        {{else}}
          {{#each this.standardFields key="key" as |field|}}
            <NpnField
              @fieldId={{field.fieldId}}
              @label={{field.label}}
              @help={{field.help}}
              @required={{field.required}}
              @optional={{field.optional}}
              @examples={{field.examples}}
              @chips={{field.chips}}
              @error={{field.error}}
              @withMetadata={{field.withMetadata}}
              @metadataUpload={{this.metadataScreenshot}}
              @metadataUploading={{this.uploading}}
              @onMetadataFiles={{this.addMetadataFile}}
              @onRemoveMetadata={{this.removeMetadataScreenshot}}
              @photoMetadataChecked={{this.photoMetadataChecked}}
              @onInput={{fn this.updateField field.key}}
              @onChip={{fn this.appendChip field.fieldId field.key}}
              @onTemplate={{fn this.appendTemplate field.fieldId field.key}}
              @photoMetadata={{this.photoMetadata}}
              @photoMetadataUsed={{this.photoMetadataUsed}}
              @onUsePhotoMetadata={{fn this.usePhotoMetadata field.fieldId field.key}}
            />
          {{/each}}
        {{/if}}
      {{/if}}

      <h3 class="npn-form-section">
        {{i18n "npn_submissions.form.sections.review"}}
      </h3>

      {{#if this.selectedStyle}}
        <div class="npn-image-form__review">
          <strong>{{i18n "npn_submissions.form.review.heading"}}</strong>
          <ul>
            <li>{{i18n "npn_submissions.form.review.item_feedback"}}</li>
            <li>{{i18n "npn_submissions.form.review.item_technical"}}</li>
            <li>{{i18n "npn_submissions.form.review.item_images"}}</li>
          </ul>
        </div>
      {{/if}}

      <p class="npn-image-form__participation">
        {{i18n "npn_submissions.form.participation_reminder"}}
      </p>

      {{#if this.showValidationSummary}}
        <div class="npn-image-form__validation" aria-live="assertive">
          <p>{{i18n "npn_submissions.form.validation.heading"}}</p>
          <ul>
            {{#each this.missingRequirements as |field|}}
              <li>
                <button
                  type="button"
                  class="npn-image-form__validation-link"
                  {{on "click" (fn this.goToField field.selector)}}
                >{{field.label}}</button>
              </li>
            {{/each}}
          </ul>
        </div>
      {{/if}}

      {{! Daily-limit reminder sits directly above the actions so it's visible
      the moment the user reaches the buttons (no need to scroll back up to the
      top-of-form notice). }}
      {{#if this.limitReached}}
        <p class="npn-image-form__notice-inline" role="alert">
          {{i18n "npn_submissions.form.daily_limit.short"}}
        </p>
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
          @label="npn_submissions.form.submit"
          @action={{this.submit}}
          @disabled={{this.submitDisabled}}
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
