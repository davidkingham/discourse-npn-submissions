import Component from "@glimmer/component";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { getOwner } from "@ember/owner";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { service } from "@ember/service";
import UserAutocompleteResults from "discourse/components/user-autocomplete-results";
import TextareaTextManipulation, {
  TextareaAutocompleteHandler,
} from "discourse/lib/textarea-text-manipulation";
import userSearch from "discourse/lib/user-search";
import DButton from "discourse/ui-kit/d-button";
import dAutocomplete from "discourse/ui-kit/modifiers/d-autocomplete";
import { i18n } from "discourse-i18n";
import NpnExpandableExample from "./npn-expandable-example";
import NpnLinkModal from "./npn-link-modal";
import NpnPromptChips from "./npn-prompt-chips";
import NpnUploadZone from "./npn-upload-zone";

// A single labelled textarea field with optional helper text, an expandable
// example, and prompt chips. The textarea is uncontrolled; `@onInput` reports
// changes and chip insertion is handled by the parent via the field id.
//
// On insert, the textarea is enhanced with two Discourse-native affordances:
//   - @mention autocomplete (same popup the composer uses), via
//     dAutocomplete.setupAutocomplete + userSearch. Honours the site setting
//     `enable_mentions`; silently skipped if it is disabled.
//   - An "Insert link" button above the textarea that opens NpnLinkModal and
//     writes `[text](url)` at the caret via TextareaTextManipulation. After
//     any programmatic write we dispatch a synthetic `input` event so the
//     parent's autosaver and live-validation gates see the change.
//
// The setup is wrapped in try/catch so a future Discourse API change can never
// break the form — the worst case is "no popup / no toolbar," typing still
// works exactly as before.
//
// When `@withMetadata` is set (Technical Details) the field also offers, above
// the textarea: an opt-in "use photo metadata" helper (when EXIF was read from
// the main image) and quick templates; and below it: the examples and a
// collapsed "upload a metadata screenshot instead" fallback. The textarea is
// always shown — typed text and/or a screenshot both satisfy the backend's
// "text OR screenshot" rule, so there is no method selector.
export default class NpnField extends Component {
  @service modal;
  @service siteSettings;

  #textarea = null;
  #textManipulation = null;

  @action
  setupTextarea(element) {
    this.#textarea = element;
    try {
      this.#textManipulation = new TextareaTextManipulation(getOwner(this), {
        textarea: element,
        eventPrefix: "npn-field",
      });
      if (this.siteSettings.enable_mentions) {
        const handler = new TextareaAutocompleteHandler(element);
        dAutocomplete.setupAutocomplete(
          getOwner(this),
          element,
          handler,
          this.#userAutocompleteOptions(element)
        );
      }
    } catch (e) {
      // Discourse-native helpers. If the API changes the worst case is the
      // popup doesn't appear — typing still works. Log so the cause is
      // visible in /logs without breaking the form for the user.
      // eslint-disable-next-line no-console
      console.warn(
        "[discourse-npn-submissions] mention autocomplete unavailable:",
        e
      );
    }
  }

  @action
  openLinkModal() {
    if (!this.#textManipulation) {
      return;
    }
    let defaultText = "";
    try {
      defaultText = this.#textManipulation.getSelected()?.value ?? "";
    } catch {
      defaultText = "";
    }
    this.modal.show(NpnLinkModal, {
      model: { defaultText, onInsert: (payload) => this.#insertLink(payload) },
    });
  }

  // --- private --------------------------------------------------------------

  #userAutocompleteOptions(textarea) {
    return {
      component: UserAutocompleteResults,
      key: UserAutocompleteResults.TRIGGER_KEY,
      width: "100%",
      treatAsTextarea: true,
      fixedTextareaPosition: true,
      autoSelectFirstSuggestion: true,
      transformComplete: (obj) => obj.username || obj.name,
      dataSource: (term) => userSearch({ term, includeGroups: true }),
      afterComplete: (text, event) => {
        event.preventDefault();
        textarea.value = text;
        textarea.focus();
        // Notify the parent's input handler (autosave + validation) that the
        // value changed via the programmatic insertion.
        textarea.dispatchEvent(new Event("input", { bubbles: true }));
      },
    };
  }

  #insertLink({ text, url }) {
    if (!this.#textManipulation || !url) {
      return;
    }
    try {
      const tm = this.#textManipulation;
      const sel = tm.getSelected();
      if (sel.start === sel.end) {
        // Caret with no selection: synthesise [linkText](url) at the caret.
        const visible = (text || "").trim() || url;
        tm.insertText(`[${visible}](${url})`);
      } else {
        // With a selection: wrap it as the link text.
        tm.applySurround(sel, "[", `](${url})`, "link_description");
      }
      // Keep autosave / validation in sync with the programmatic write.
      this.#textarea?.dispatchEvent(new Event("input", { bubbles: true }));
      this.#textarea?.focus();
    } catch (e) {
      // eslint-disable-next-line no-console
      console.warn("[discourse-npn-submissions] insert link failed:", e);
    }
  }

  // `@compact` shortens the default textarea height so optional fields read
  // as quieter context next to the page's primary required field. Behaviour
  // is unchanged — only `min-height` differs (see
  // .npn-image-form__field--compact in the stylesheet).
  <template>
    <div
      class="npn-image-form__field
        {{if @error 'npn-image-form__field--needs-attention'}}
        {{if @compact 'npn-image-form__field--compact'}}"
    >
      <label for={{@fieldId}}>
        {{@label}}
        {{#if @required}}
          <span class="npn-required">{{i18n "npn_submissions.form.required"}}</span>
        {{else if @optional}}
          <span class="npn-optional">{{i18n "npn_submissions.form.optional"}}</span>
        {{/if}}
      </label>

      {{#if @help}}
        <p class="npn-help">{{@help}}</p>
      {{/if}}

      {{#if @examples.summary}}
        <NpnExpandableExample @summary={{@examples.summary}}>
          <ul class="npn-image-form__specs">
            {{#each @examples.items as |item|}}
              <li>{{item}}</li>
            {{/each}}
          </ul>
        </NpnExpandableExample>
      {{else if @examples.neutral}}
        <p class="npn-help">{{@examples.neutral}}</p>
      {{/if}}

      {{#if @chips}}
        <NpnPromptChips @chips={{@chips}} @onPick={{@onChip}} />
      {{/if}}

      {{#if @withMetadata}}
        {{! Photo metadata: opt-in starting point when EXIF was read from the main
        image; a calm hint once we've checked and found none. Inserting is the same
        append-after-blank-line / never-overwrite behaviour as the templates. }}
        {{#if @photoMetadata}}
          <div class="npn-photo-metadata">
            {{#if @photoMetadataUsed}}
              {{! Keep the box in place (no layout jump); just confirm it was added
              and offer a quiet, deliberate "insert again". }}
              <p class="npn-photo-metadata__title">
                {{i18n "npn_submissions.form.photo_metadata.added"}}
              </p>
              <p class="npn-photo-metadata__help">
                {{i18n "npn_submissions.form.photo_metadata.added_help"}}
              </p>
              <button
                type="button"
                class="npn-photo-metadata__again"
                {{on "click" (fn @onUsePhotoMetadata @photoMetadata)}}
              >{{i18n "npn_submissions.form.photo_metadata.insert_again"}}</button>
            {{else}}
              <p class="npn-photo-metadata__title">
                {{i18n "npn_submissions.form.photo_metadata.found"}}
              </p>
              <p class="npn-photo-metadata__help">
                {{i18n "npn_submissions.form.photo_metadata.found_help"}}
              </p>
              <DButton
                @translatedLabel={{i18n "npn_submissions.form.photo_metadata.use"}}
                @action={{fn @onUsePhotoMetadata @photoMetadata}}
                class="btn-default btn-small npn-photo-metadata__button"
              />
            {{/if}}
          </div>
        {{else if @photoMetadataChecked}}
          <p class="npn-help npn-photo-metadata__none">
            {{i18n "npn_submissions.form.photo_metadata.none"}}
          </p>
        {{/if}}

        {{! Quick templates adapt to photo-metadata state: once metadata exists
        (found or inserted) the EXIF template would be redundant, so we drop it and
        reframe the rest as "add more context". }}
        <div class="npn-chips npn-tech-templates">
          <span class="npn-chips__intro">
            {{#if @photoMetadata}}
              {{i18n "npn_submissions.form.technical_templates.label_more"}}
            {{else}}
              {{i18n "npn_submissions.form.technical_templates.label"}}
            {{/if}}
          </span>
          {{#unless @photoMetadata}}
            <button
              type="button"
              class="npn-chip"
              {{on
                "click"
                (fn
                  @onTemplate
                  (i18n "npn_submissions.form.technical_templates.basic_exif.body")
                )
              }}
            >{{i18n
                "npn_submissions.form.technical_templates.basic_exif.label"
              }}</button>
          {{/unless}}
          <button
            type="button"
            class="npn-chip"
            {{on
              "click"
              (fn
                @onTemplate
                (i18n
                  "npn_submissions.form.technical_templates.field_technique.body"
                )
              )
            }}
          >{{i18n
              "npn_submissions.form.technical_templates.field_technique.label"
            }}</button>
          <button
            type="button"
            class="npn-chip"
            {{on
              "click"
              (fn
                @onTemplate
                (i18n
                  "npn_submissions.form.technical_templates.processing_notes.body"
                )
              )
            }}
          >{{i18n
              "npn_submissions.form.technical_templates.processing_notes.label"
            }}</button>
        </div>
      {{/if}}

      {{! Insert-link toolbar sits directly above the textarea so the button is
      adjacent to the field it acts on. The action is a no-op until didInsert
      binds textManipulation (microseconds later), so there's no race risk. }}
      <div
        class="npn-field__toolbar"
        role="toolbar"
        aria-label={{i18n "npn_submissions.form.toolbar.label"}}
      >
        <DButton
          @icon="link"
          @label="npn_submissions.form.toolbar.insert_link"
          @action={{this.openLinkModal}}
          class="btn-flat btn-small npn-field__toolbar-button"
        />
      </div>

      <textarea
        id={{@fieldId}}
        aria-invalid={{if @error "true"}}
        {{on "input" @onInput}}
        {{didInsert this.setupTextarea}}
      ></textarea>

      {{#if @withMetadata}}
        {{! Examples sit below the textarea as supporting guidance. }}
        <NpnExpandableExample
          @summary={{i18n "npn_submissions.form.technical_examples.summary"}}
        >
          <ul class="npn-image-form__specs">
            <li>{{i18n "npn_submissions.form.technical_examples.camera"}}</li>
            <li>{{i18n "npn_submissions.form.technical_examples.lens"}}</li>
            <li>{{i18n "npn_submissions.form.technical_examples.field"}}</li>
            <li>{{i18n "npn_submissions.form.technical_examples.processing"}}</li>
          </ul>
        </NpnExpandableExample>

        {{! Metadata screenshot: shown directly once uploaded; otherwise a quiet,
        collapsed fallback for when EXIF was stripped or is incomplete. }}
        {{#if @metadataUpload}}
          <div class="npn-field__metadata">
            <label>{{i18n "npn_submissions.form.metadata_screenshot.label"}}</label>
            <div class="npn-image-form__image-row">
              <div class="npn-image-form__thumb">
                <img
                  src={{@metadataUpload.url}}
                  alt={{@metadataUpload.original_filename}}
                />
              </div>
              <DButton
                @icon="trash-can"
                @action={{@onRemoveMetadata}}
                @title="npn_submissions.form.images.remove"
                @ariaLabel="npn_submissions.form.images.remove"
                class="btn-flat"
              />
            </div>
          </div>
        {{else}}
          <details class="npn-expandable npn-field__metadata-fallback">
            <summary>
              {{i18n "npn_submissions.form.metadata_screenshot.fallback_label"}}
            </summary>
            <div class="npn-expandable__content">
              <p class="npn-help">
                {{i18n "npn_submissions.form.metadata_screenshot.fallback_help"}}
              </p>
              <NpnUploadZone
                @accept="image/*"
                @disabled={{@metadataUploading}}
                @label={{i18n "npn_submissions.form.upload.metadata"}}
                @onFiles={{@onMetadataFiles}}
              />
            </div>
          </details>
        {{/if}}
      {{/if}}

      {{#if @error}}
        <p class="npn-field__error" aria-live="polite">{{@error}}</p>
      {{/if}}
    </div>
  </template>
}
