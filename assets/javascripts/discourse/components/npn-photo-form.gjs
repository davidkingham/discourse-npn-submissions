import { tracked } from "@glimmer/tracking";
import { fn, get, hash } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { schedule } from "@ember/runloop";
import bodyClass from "discourse/helpers/body-class";
import DButton from "discourse/ui-kit/d-button";
import dDiscourseTag from "discourse/ui-kit/helpers/d-discourse-tag";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import { focusFieldBySelector } from "../lib/npn-focus-field";
import {
  compactCameraLine,
  foldInDepthFields,
  mergeTechnicalDetails,
} from "../lib/npn-photo-form";
import NpnAskIdeas from "./npn-ask-ideas";
import NpnAutosaveStatus from "./npn-autosave-status";
import NpnExpandableExample from "./npn-expandable-example";
import NpnField from "./npn-field";
import NpnImageForm from "./npn-image-form";
import NpnImageList from "./npn-image-list";
import NpnLockedImages from "./npn-locked-images";
import NpnTagChooser from "./npn-tag-chooser";
import NpnTagMultiSelect from "./npn-tag-multi-select";
import NpnWeeklyChallengePanel from "./npn-weekly-challenge-panel";

// Things a member could ask critics, as form.chips.<focus>.<key> entries (the
// classic form's suggested wording, reused).
const ASK_IDEAS = [
  "artistic.mood_feeling",
  "artistic.composition",
  "artistic.visual_flow",
  "artistic.distractions",
  "technical.color",
  "technical.processing",
  "technical.sharpness_focus",
  "technical.exposure",
  "both.unresolved",
];

const REACTION_IDEAS = [
  "first_notice",
  "feeling",
  "eye_path",
  "about",
  "lingering",
  "change",
];

// Above this many allowed tags, tappable chips stop being quicker than search.
const MAX_TAG_CHIPS = 30;

// The photo-first image form for Image for Critique and the Weekly Challenge.
// Which of the two forms opens is decided in routes/submit.js
// (lib/npn-form-choice.js); the classic form is one link away.
//
// It is the classic form with a different face. Uploads, drafts, autosave,
// preview, validation and submit are all inherited from NpnImageForm, and it
// sends the same payload, so the server, the post it builds and "edit with
// form" need to know nothing about it. What changes is what the member is
// asked:
//   - no Critique Style cards: it is a Standard critique unless "first
//     impressions first" is switched on (Initial Reaction). In-Depth's three
//     reflective boxes become one optional "story" box;
//   - no Feedback Focus cards: the focus is a row of three pills above the
//     question, with "both" already chosen;
//   - camera data read from the file is a caption under the photograph with an
//     "include in post" tick, and is merged into Technical Details on save.
//     "Edit" moves it into the "how it was made" box as ordinary text, for
//     files whose data is wrong or incomplete (a manual lens, say).
export default class NpnPhotoForm extends NpnImageForm {
  @tracked includeCameraData = true;
  // True once the camera data has been moved into the box to be edited: from
  // then on the member's text is the only copy.
  @tracked cameraDataEdited = false;
  // The optional boxes start as one-line rows and open on request (or when
  // they already hold something, or are needed).
  @tracked storyExpanded = false;
  @tracked madeExpanded = false;

  constructor() {
    super(...arguments);
    // Plain assignments: reading a tracked value here first would trip
    // Glimmer's "updated after use" assertion. A post being edited was already
    // hydrated by the parent constructor and keeps its own style and focus.
    if (!this.editing) {
      this.selectedStyle = "standard";
      this.selectedFocus = "both";
    }
  }

  get isReaction() {
    return this.selectedStyle === "reaction";
  }

  // Unlike the classic form, the style and focus are never blank here, so on
  // their own they aren't worth a saved draft.
  get hasMeaningfulContent() {
    return (
      this.title.trim().length > 0 ||
      this.images.length > 0 ||
      this.tags.length > 0 ||
      !!this.metadataScreenshot ||
      Object.values(this.fields).some((v) => (v || "").trim().length > 0)
    );
  }

  // From here the "other form" is the classic one.
  get otherFormName() {
    return "classic";
  }

  get feedbackUrl() {
    // encodeURIComponent, not URLSearchParams: Ember reads "+" literally.
    const title = encodeURIComponent(
      i18n("npn_submissions.photo_form.feedback_topic_title")
    );
    const categoryId =
      this.siteSettings.npn_submissions_new_image_form_feedback_category_id;
    return categoryId
      ? `/new-topic?title=${title}&category_id=${categoryId}`
      : `/new-topic?title=${title}`;
  }

  hydrate(draft) {
    super.hydrate(draft);
    // Decided from the draft, not from what was just set: this also runs from
    // the constructor (editing a post), where reading a tracked value and then
    // writing it trips Glimmer's "updated after use" assertion.
    if (draft.critique_style === "in_depth") {
      this.fields = foldInDepthFields(draft.data?.fields);
    }
    if (draft.critique_style !== "reaction") {
      this.selectedStyle = "standard";
    }
    this.selectedFocus = draft.data?.feedback_focus || "both";
    this.includeCameraData = true;
    this.cameraDataEdited = false;
    this.storyExpanded = false;
    this.madeExpanded = false;
  }

  resetForm() {
    super.resetForm();
    this.selectedStyle = "standard";
    this.selectedFocus = "both";
    this.includeCameraData = true;
    this.cameraDataEdited = false;
    this.storyExpanded = false;
    this.madeExpanded = false;
  }

  buildPayload() {
    const payload = super.buildPayload();
    payload.data.form_version = "photo_first";
    payload.data.fields = {
      ...this.fields,
      technical_details: mergeTechnicalDetails(
        this.includedCameraData,
        this.fields.technical_details
      ),
    };
    return payload;
  }

  // --- Photograph ------------------------------------------------------------

  // One caption line for the main photograph's camera data.
  get cameraLine() {
    const main = this.images[0];
    return main
      ? compactCameraLine(this.photoMetadataById[main.upload.id])
      : "";
  }

  // What the tick adds to the post: every photograph's data, labeled when
  // there are several (the classic form's "use photo metadata" text).
  get includedCameraData() {
    return this.includeCameraData && !this.cameraDataEdited
      ? this.photoMetadata
      : null;
  }

  get showCameraLine() {
    return !!this.cameraLine && !this.cameraDataEdited;
  }

  get hasTechnicalContent() {
    return !!this.includedCameraData || super.hasTechnicalContent;
  }

  @action
  toggleCameraData(event) {
    this.includeCameraData = event.target.checked;
    this.scheduleAutosave();
  }

  // Put the camera data into the "how it was made" box, ahead of anything
  // already typed there, and take the member to it.
  @action
  editCameraData() {
    this.fields = {
      ...this.fields,
      technical_details: mergeTechnicalDetails(
        this.photoMetadata,
        this.fields.technical_details
      ),
    };
    this.cameraDataEdited = true;
    this.scheduleAutosave();
    schedule("afterRender", () => {
      focusFieldBySelector("#npn-field-technical_details")?.scrollIntoView({
        behavior: "smooth",
        block: "center",
      });
    });
  }

  @action
  setImages(next) {
    const first = this.images.length === 0 && next.length > 0;
    super.setImages(next);
    if (next.length === 0) {
      this.cameraDataEdited = false;
    }
    // The title sits under the photograph, where it is easy to miss: once the
    // first photograph is in, put the cursor there.
    if (first && this.title.trim().length === 0) {
      schedule("afterRender", () => this.revealTitle());
    }
  }

  // A tall photograph pushes the title below the fold. Once the photograph
  // has its size, bring the photograph and its title into view together (the
  // column's scroll margin clears the site header) and then place the cursor.
  revealTitle() {
    const column = document.querySelector(".npn-photo-form__photo");
    const img = column?.querySelector("#npn-images-field img");
    const reveal = () => {
      const title = document.querySelector("#npn-title");
      if (!title) {
        return;
      }
      if (title.getBoundingClientRect().bottom > window.innerHeight) {
        column.scrollIntoView({ behavior: "smooth", block: "start" });
      }
      title.focus({ preventScroll: true });
    };
    if (img && !img.complete) {
      img.addEventListener("load", reveal, { once: true });
      img.addEventListener("error", reveal, { once: true });
    } else {
      reveal();
    }
  }

  // --- Tags ------------------------------------------------------------------

  get showTagChips() {
    return (
      this.tagsConstrained &&
      this.allowedTags.length > 0 &&
      this.allowedTags.length <= MAX_TAG_CHIPS
    );
  }

  get tagChips() {
    return this.allowedTags.map((name) => ({
      name,
      selected: this.tags.includes(name),
    }));
  }

  @action
  toggleTag(name) {
    this.updateTags(
      this.tags.includes(name)
        ? this.tags.filter((tag) => tag !== name)
        : [...this.tags, name]
    );
  }

  // --- What to ask -----------------------------------------------------------

  // The feedback focus as three pills. "Both" is chosen from the start, so a
  // member who has no preference does nothing.
  get focusPills() {
    return ["artistic", "technical", "both"].map((id) => ({
      id,
      label: i18n(`npn_submissions.photo_form.focus.${id}`),
      selected: this.selectedFocus === id,
    }));
  }

  // Sentences a member could borrow when they can't think what to ask.
  // A Weekly Challenge entry leads with questions about the theme.
  get askIdeas() {
    const ideas = ASK_IDEAS.map((key) => ({
      key,
      text: i18n(`npn_submissions.form.chips.${key}.suggested`),
    }));
    return [...this.weeklyIdeas(["theme_fit", "theme_reading"]), ...ideas];
  }

  weeklyIdeas(keys) {
    if (!this.isWeeklyChallenge) {
      return [];
    }
    return keys.map((key) => ({
      key,
      text: i18n(`npn_submissions.photo_form.weekly.ideas.${key}`),
    }));
  }

  // Open questions for Initial Reaction. They never state the photographer's
  // intent, which the classic form's shared chips did.
  get reactionIdeas() {
    const ideas = REACTION_IDEAS.map((key) => ({
      key,
      text: i18n(`npn_submissions.photo_form.reaction_ideas.${key}`),
    }));
    return [...this.weeklyIdeas(["theme_seen"]), ...ideas];
  }

  // "First impressions first" is the Initial Reaction style. The request the
  // member has already typed follows them across: in a reaction it belongs
  // with the hidden notes (feedback_after), otherwise it is the main question.
  @action
  toggleReaction(event) {
    const reaction = event.target.checked;
    const [from, to] = reaction
      ? ["feedback_requested", "feedback_after"]
      : ["feedback_after", "feedback_requested"];
    const moving = (this.fields[from] || "").trim();
    if (moving && !(this.fields[to] || "").trim()) {
      this.fields = { ...this.fields, [to]: this.fields[from], [from]: "" };
    }
    this.selectedStyle = reaction ? "reaction" : "standard";
    // The required box has just changed, so a "this is required" left over
    // from an earlier submit attempt would be scolding for nothing.
    this.attemptedSubmit = false;
    this.scheduleAutosave();
  }

  field(key, name, { required = false, compact = false } = {}) {
    const missing =
      required &&
      this.attemptedSubmit &&
      (this.fields[key] || "").trim().length === 0;
    return {
      key,
      fieldId: `npn-field-${key}`,
      label: i18n(`npn_submissions.photo_form.${name}.label`),
      help: i18n(`npn_submissions.photo_form.${name}.help`),
      required,
      compact,
      error: missing ? i18n("npn_submissions.form.field_required") : null,
    };
  }

  // The one required box: the request, or the open questions in a reaction.
  get askField() {
    return this.isReaction
      ? this.field("questions_for_viewers", "questions", { required: true })
      : this.field("feedback_requested", "ask", { required: true });
  }

  get afterField() {
    return this.field("feedback_after", "after", { compact: true });
  }

  // For a Weekly Challenge the story box asks about the theme first. It is the
  // same About This Image answer either way.
  get storyName() {
    return this.isWeeklyChallenge ? "weekly.story" : "story";
  }

  get storyField() {
    return this.field("about_this_image", this.storyName, { compact: true });
  }

  get storyAddLabel() {
    return i18n(`npn_submissions.photo_form.${this.storyName}.add`);
  }

  // The tag the server adds to every Weekly Challenge entry, shown in the
  // summary so the member sees where the post is going.
  get weeklyTag() {
    return this.isWeeklyChallenge
      ? this.siteSettings.npn_submissions_weekly_challenge_tag
      : null;
  }

  // The server requires Technical Details for a "technical" focus. Included
  // camera data already meets that, so the box is only demanded without it.
  get madeRequired() {
    return this.technicalRequired && !this.includedCameraData;
  }

  // Camera data sits under the photograph, but members look for it where they
  // type their settings, so that spot says what happened to it: "included"
  // when it is going into the post, "none" when the file carried none.
  get cameraDataState() {
    if (this.cameraDataEdited) {
      return null;
    }
    if (this.photoMetadata) {
      return this.includeCameraData ? "included" : null;
    }
    return this.photoMetadataChecked && this.images.length > 0 ? "none" : null;
  }

  get madeAddNote() {
    if (this.cameraDataState === "included") {
      return i18n("npn_submissions.photo_form.made.note_included");
    }
    if (this.cameraDataState === "none") {
      return i18n("npn_submissions.photo_form.made.note_none");
    }
    return i18n("npn_submissions.photo_form.optional");
  }

  get madeHelp() {
    if (this.madeRequired) {
      return i18n("npn_submissions.photo_form.made.help_required");
    }
    if (this.cameraDataState === "included" && this.cameraLine) {
      return i18n("npn_submissions.photo_form.made.help_included", {
        data: this.cameraLine,
      });
    }
    if (this.cameraDataState === "none") {
      return i18n("npn_submissions.photo_form.made.help_none");
    }
    return null;
  }

  get madeField() {
    const base = this.field("technical_details", "made");
    return {
      ...base,
      help: this.madeHelp || base.help,
      required: this.madeRequired,
      error: this.technicalMissing
        ? i18n("npn_submissions.photo_form.made.required_error")
        : null,
    };
  }

  // What the inherited validation walks for required answers.
  get questionFields() {
    return [this.askField];
  }

  get missingRequirements() {
    const labels = {
      "#npn-images-field": i18n("npn_submissions.photo_form.photo.label"),
      "#npn-tags-field": i18n("npn_submissions.photo_form.tags.label"),
      "#npn-field-technical_details": i18n(
        "npn_submissions.photo_form.made.label"
      ),
    };
    return super.missingRequirements.map((item) => ({
      ...item,
      label: labels[item.selector] || item.label,
    }));
  }

  get storyOpen() {
    return (
      this.storyExpanded ||
      (this.fields.about_this_image || "").trim().length > 0
    );
  }

  get madeOpen() {
    return (
      this.madeExpanded ||
      this.madeRequired ||
      !!this.metadataScreenshot ||
      (this.fields.technical_details || "").trim().length > 0
    );
  }

  @action
  openStory() {
    this.storyExpanded = true;
  }

  @action
  openMade() {
    this.madeExpanded = true;
  }

  // --- What critics will see -------------------------------------------------

  get summaryThumb() {
    return this.images[0]?.upload.url;
  }

  get summaryStyle() {
    return i18n(
      `npn_submissions.photo_form.summary.styles.${this.selectedStyle}`
    );
  }

  get summaryFocus() {
    return i18n(
      `npn_submissions.photo_form.summary.focuses.${this.selectedFocus}`
    );
  }

  <template>
    {{bodyClass "npn-submit-page--photo-form"}}

    <form class="npn-image-form npn-photo-form" {{on "submit" this.submit}}>
      {{#unless this.editing}}
        <p class="npn-form-invite npn-form-invite--testing">
          <span class="npn-photo-form__badge">
            {{i18n "npn_submissions.photo_form.badge"}}
          </span>
          <span class="npn-form-invite__text">
            {{i18n "npn_submissions.photo_form.testing"}}
          </span>
          <span class="npn-form-invite__links">
            <a
              href={{this.feedbackUrl}}
              target="_blank"
              rel="noopener noreferrer"
            >
              {{i18n "npn_submissions.photo_form.feedback_link"}}
            </a>
            <a href={{this.otherFormUrl}} {{on "click" this.switchForm}}>
              {{i18n "npn_submissions.photo_form.back_to_classic"}}
            </a>
          </span>
        </p>
      {{/unless}}

      <header class="npn-photo-form__header">
        <h2>{{this.introTitle}}</h2>
        <p class="npn-image-form__lead">{{this.introLead}}</p>

        {{#if this.editedOutsideForm}}
          <div class="npn-image-form__notice" role="alert">
            {{i18n "npn_submissions.form.edit.edited_outside_form"}}
          </div>
        {{/if}}

        {{#unless this.editing}}
          <NpnExpandableExample
            @summary={{i18n "npn_submissions.form.intro.help_summary"}}
          >
            <p>{{i18n "npn_submissions.form.intro.exchange"}}</p>
            <p>{{i18n "npn_submissions.form.intro.daily_limit"}}</p>
            <p class="npn-image-form__help-links">
              <span>{{i18n "npn_submissions.form.intro.help_prefix"}}</span>
              <a href="/submit?type=help">
                {{i18n "npn_submissions.form.intro.help_link"}}
              </a>
              {{#if this.critiqueGuideUrl}}
                <a href={{this.critiqueGuideUrl}}>
                  {{i18n "npn_submissions.form.intro.help_guide"}}
                </a>
              {{/if}}
            </p>
          </NpnExpandableExample>
        {{/unless}}
      </header>

      {{#if this.showWeeklyPanel}}
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
            @translatedLabel={{this.startNewLabel}}
            @action={{this.startNew}}
            @icon="plus"
            class="btn-default npn-image-form__start-new-button"
          />
        </div>
      {{/if}}

      <div class="npn-photo-form__layout">
        <section class="npn-photo-form__photo">
          <div
            id="npn-images-field"
            class="npn-photo-form__stage
              {{if this.images.length 'has-photo'}}
              {{if this.imagesMissing 'needs-attention'}}"
          >
            {{#if this.imagesLocked}}
              <NpnLockedImages @images={{this.lockedImages}} />
            {{else}}
              <NpnImageList
                @images={{this.images}}
                @onChange={{this.setImages}}
                @uploadFile={{this.uploadFile}}
                @uploading={{this.uploading}}
                @maxImages={{this.maxImages}}
                @uploadLabel={{i18n "npn_submissions.photo_form.photo.drop"}}
                @addMoreLabel={{i18n
                  "npn_submissions.photo_form.photo.add_more"
                }}
                @addMoreHelp={{i18n
                  "npn_submissions.photo_form.photo.add_more_help"
                }}
                @enableNotes={{this.hasMultipleImages}}
                @notePlaceholder={{i18n
                  "npn_submissions.form.images.note_placeholder"
                }}
                @badge="main"
                @mainBadgeText={{i18n "npn_submissions.form.images.main_badge"}}
                @singleLarge={{true}}
                @showLargeImageWarning={{true}}
                @onFileAdded={{this.captureImageMetadata}}
              />
            {{/if}}
            {{#if this.imagesMissing}}
              <p class="npn-image-form__prompt" aria-live="polite">
                {{i18n "npn_submissions.form.prompts.add_image"}}
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
              placeholder={{i18n
                "npn_submissions.photo_form.title_placeholder"
              }}
              aria-label={{i18n "npn_submissions.form.title_label"}}
              aria-required="true"
              {{on "input" this.updateTitle}}
            />
            {{#if this.titleMissing}}
              <p class="npn-image-form__prompt" aria-live="polite">
                {{i18n "npn_submissions.form.prompts.enter_title"}}
              </p>
            {{/if}}

            {{#if this.showCameraLine}}
              <div class="npn-photo-form__camera">
                {{dIcon "camera"}}
                <span
                  class="npn-photo-form__camera-line"
                  title={{i18n "npn_submissions.photo_form.camera.label"}}
                >{{this.cameraLine}}</span>
                <label class="npn-photo-form__camera-include">
                  <input
                    type="checkbox"
                    checked={{this.includeCameraData}}
                    {{on "change" this.toggleCameraData}}
                  />
                  {{i18n "npn_submissions.photo_form.camera.include"}}
                </label>
                <DButton
                  class="btn-transparent npn-photo-form__camera-edit"
                  @icon="pencil"
                  @label="npn_submissions.photo_form.camera.edit"
                  @title="npn_submissions.photo_form.camera.edit_title"
                  @action={{this.editCameraData}}
                />
              </div>
            {{else if this.cameraDataEdited}}
              <div class="npn-photo-form__camera">
                {{dIcon "camera"}}
                <span class="npn-photo-form__camera-line">
                  {{i18n "npn_submissions.photo_form.camera.edited"}}
                </span>
              </div>
            {{/if}}
          </div>

          <div
            id="npn-tags-field"
            class="npn-photo-form__tags
              {{if this.tagsMissing 'needs-attention'}}"
          >
            <span id="npn-tags-label" class="npn-photo-form__label">
              {{i18n "npn_submissions.photo_form.tags.label"}}
            </span>
            {{#if this.showTagChips}}
              <div
                class="npn-photo-form__tag-chips"
                role="group"
                aria-labelledby="npn-tags-label"
              >
                {{#each this.tagChips key="name" as |tag|}}
                  <button
                    type="button"
                    class="npn-photo-form__pill npn-photo-form__tag-chip
                      {{if tag.selected 'is-selected'}}"
                    aria-pressed={{if tag.selected "true" "false"}}
                    {{on "click" (fn this.toggleTag tag.name)}}
                  >{{dDiscourseTag tag.name noHref=true}}</button>
                {{/each}}
              </div>
            {{else if this.tagsConstrained}}
              <NpnTagMultiSelect
                @value={{this.tags}}
                @content={{this.allowedTagContent}}
                @onChange={{this.updateTags}}
                @options={{hash filterable=true}}
              />
            {{else}}
              <NpnTagChooser
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
        </section>

        <section class="npn-photo-form__questions">
          {{#let this.askField as |field|}}
            <NpnField
              @fieldId={{field.fieldId}}
              @label={{field.label}}
              @help={{field.help}}
              @required={{field.required}}
              @error={{field.error}}
              @value={{get this.fields field.key}}
              @categoryId={{this.categoryId}}
              @onChange={{fn this.updateField field.key}}
            >
              <:before>
                <div class="npn-photo-form__focus">
                  <span
                    id="npn-focus-label"
                    class="npn-photo-form__focus-label"
                  >
                    {{i18n "npn_submissions.photo_form.focus.label"}}
                  </span>
                  <div
                    id="npn-focus-cards"
                    class="npn-photo-form__focus-pills"
                    role="group"
                    aria-labelledby="npn-focus-label"
                  >
                    {{#each this.focusPills key="id" as |pill|}}
                      <button
                        type="button"
                        class="npn-photo-form__pill
                          {{if pill.selected 'is-selected'}}"
                        aria-pressed={{if pill.selected "true" "false"}}
                        {{on "click" (fn this.selectFocus pill.id)}}
                      >{{pill.label}}</button>
                    {{/each}}
                  </div>
                </div>
              </:before>
              <:default>
                {{#if this.isReaction}}
                  <NpnAskIdeas
                    @ideas={{this.reactionIdeas}}
                    @summary={{i18n
                      "npn_submissions.photo_form.ideas.reaction_summary"
                    }}
                    @onPick={{fn this.appendChip field.fieldId field.key}}
                  />
                {{else}}
                  <NpnAskIdeas
                    @ideas={{this.askIdeas}}
                    @summary={{i18n "npn_submissions.photo_form.ideas.summary"}}
                    @onPick={{fn this.appendChip field.fieldId field.key}}
                  />
                {{/if}}
              </:default>
            </NpnField>
          {{/let}}

          <label class="npn-photo-form__reaction" for="npn-reaction">
            <input
              id="npn-reaction"
              type="checkbox"
              checked={{this.isReaction}}
              {{on "change" this.toggleReaction}}
            />
            <span class="npn-photo-form__reaction-text">
              <span class="npn-photo-form__reaction-label">
                {{i18n "npn_submissions.photo_form.reaction.label"}}
              </span>
              <span class="npn-help">
                {{i18n "npn_submissions.photo_form.reaction.help"}}
              </span>
            </span>
          </label>

          <div
            class="npn-photo-form__extras
              {{if this.isReaction 'npn-photo-form__extras--hidden'}}"
          >
            {{#if this.isReaction}}
              <p class="npn-photo-form__hidden-heading">
                {{dIcon "far-eye-slash"}}
                <span>
                  <strong>
                    {{i18n "npn_submissions.photo_form.hidden.label"}}
                  </strong>
                  {{i18n "npn_submissions.photo_form.hidden.help"}}
                </span>
              </p>

              {{#let this.afterField as |field|}}
                <NpnField
                  @fieldId={{field.fieldId}}
                  @label={{field.label}}
                  @help={{field.help}}
                  @optional={{true}}
                  @compact={{field.compact}}
                  @value={{get this.fields field.key}}
                  @categoryId={{this.categoryId}}
                  @onChange={{fn this.updateField field.key}}
                >
                  <NpnAskIdeas
                    @ideas={{this.askIdeas}}
                    @summary={{i18n "npn_submissions.photo_form.ideas.summary"}}
                    @onPick={{fn this.appendChip field.fieldId field.key}}
                  />
                </NpnField>
              {{/let}}
            {{/if}}

            {{#if this.storyOpen}}
              {{#let this.storyField as |field|}}
                <NpnField
                  @fieldId={{field.fieldId}}
                  @label={{field.label}}
                  @help={{field.help}}
                  @optional={{true}}
                  @compact={{field.compact}}
                  @value={{get this.fields field.key}}
                  @categoryId={{this.categoryId}}
                  @onChange={{fn this.updateField field.key}}
                />
              {{/let}}
            {{else}}
              <button
                type="button"
                class="npn-photo-form__add-row"
                {{on "click" this.openStory}}
              >
                {{dIcon "plus"}}
                <span>{{this.storyAddLabel}}</span>
                <span class="npn-photo-form__add-row-note">
                  {{i18n "npn_submissions.photo_form.optional"}}
                </span>
              </button>
            {{/if}}

            {{#if this.madeOpen}}
              {{#let this.madeField as |field|}}
                <NpnField
                  @fieldId={{field.fieldId}}
                  @label={{field.label}}
                  @help={{field.help}}
                  @required={{field.required}}
                  @optional={{if field.required false true}}
                  @compact={{true}}
                  @error={{field.error}}
                  @withMetadata={{true}}
                  @cameraDataRead={{this.photoMetadata}}
                  @metadataUpload={{this.metadataScreenshot}}
                  @metadataUploading={{this.uploading}}
                  @onMetadataFiles={{this.addMetadataFile}}
                  @onRemoveMetadata={{this.removeMetadataScreenshot}}
                  @value={{get this.fields field.key}}
                  @categoryId={{this.categoryId}}
                  @onChange={{fn this.updateField field.key}}
                  @onTemplate={{fn this.appendTemplate field.fieldId field.key}}
                />
              {{/let}}
            {{else}}
              <button
                type="button"
                class="npn-photo-form__add-row"
                {{on "click" this.openMade}}
              >
                {{dIcon "plus"}}
                <span>{{i18n "npn_submissions.photo_form.made.add"}}</span>
                <span class="npn-photo-form__add-row-note">
                  {{this.madeAddNote}}
                </span>
              </button>
            {{/if}}
          </div>
        </section>
      </div>

      <section class="npn-photo-form__finish">
        <div class="npn-photo-form__summary">
          <div class="npn-photo-form__summary-thumb">
            {{#if this.summaryThumb}}
              <img src={{this.summaryThumb}} alt="" />
            {{else}}
              {{dIcon "image"}}
            {{/if}}
          </div>
          <div class="npn-photo-form__summary-body">
            <span class="npn-photo-form__summary-heading">
              {{i18n "npn_submissions.photo_form.summary.heading"}}
            </span>
            <span class="npn-photo-form__summary-title">
              {{#if this.title}}
                {{this.title}}
              {{else}}
                {{i18n "npn_submissions.photo_form.summary.untitled"}}
              {{/if}}
            </span>
            <span class="npn-photo-form__summary-meta">
              <span>{{this.summaryStyle}}</span>
              <span>{{this.summaryFocus}}</span>
              {{#if this.weeklyTag}}
                <span>{{dDiscourseTag this.weeklyTag noHref=true}}</span>
              {{/if}}
              {{#each this.tags as |tag|}}
                <span>{{dDiscourseTag tag noHref=true}}</span>
              {{/each}}
            </span>
          </div>
        </div>

        <div class="npn-image-form__processing-examples">
          <label class="npn-image-form__checkbox" for="npn-processing-examples">
            <input
              id="npn-processing-examples"
              type="checkbox"
              checked={{this.processingExamplesAllowed}}
              {{on "change" this.updateProcessingExamples}}
            />
            <span>
              {{i18n "npn_submissions.form.processing_examples.label"}}
            </span>
          </label>
          <p class="npn-help">
            {{i18n "npn_submissions.form.processing_examples.help"}}
          </p>
        </div>

        <p class="npn-image-form__participation">
          {{i18n "npn_submissions.form.participation_reminder"}}
        </p>
      </section>

      {{#if this.showValidationSummary}}
        <div class="npn-image-form__validation" aria-live="assertive">
          <p>{{i18n "npn_submissions.form.validation.heading"}}</p>
          <ul>
            {{#each this.missingRequirements as |item|}}
              <li>
                <button
                  type="button"
                  class="npn-image-form__validation-link"
                  {{on "click" (fn this.goToField item.selector)}}
                >{{item.label}}</button>
              </li>
            {{/each}}
          </ul>
        </div>
      {{/if}}

      {{#if this.limitReached}}
        <p class="npn-image-form__notice-inline" role="alert">
          {{i18n "npn_submissions.form.daily_limit.short"}}
        </p>
      {{/if}}

      <div class="npn-image-form__actions">
        <DButton
          @label={{if
            this.editing
            "npn_submissions.form.edit.save"
            "npn_submissions.form.submit"
          }}
          @action={{this.submit}}
          @disabled={{this.submitDisabled}}
          @isLoading={{this.submitting}}
          class="btn-primary"
        />
        <DButton
          @label="npn_submissions.form.preview.button"
          @action={{this.openPreview}}
          @disabled={{this.busy}}
          @isLoading={{this.previewing}}
          class="btn-default"
        />
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
          <NpnAutosaveStatus @autosaver={{this.autosaver}} />
        {{/if}}
      </div>
    </form>
  </template>
}
