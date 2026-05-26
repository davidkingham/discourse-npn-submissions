import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import NpnExpandableExample from "./npn-expandable-example";
import NpnPromptChips from "./npn-prompt-chips";
import NpnUploadZone from "./npn-upload-zone";

// A single labelled textarea field with optional helper text, an expandable
// example, and prompt chips. The textarea is uncontrolled; `@onInput` reports
// changes and chip insertion is handled by the parent via the field id.
//
// When `@withMetadata` is set (Technical Details) the field also offers, above
// the textarea: an opt-in "use photo metadata" helper (when EXIF was read from
// the main image) and quick templates; and below it: the examples and a
// collapsed "upload a metadata screenshot instead" fallback. The textarea is
// always shown — typed text and/or a screenshot both satisfy the backend's
// "text OR screenshot" rule, so there is no method selector.
const NpnField = <template>
  <div
    class="npn-image-form__field
      {{if @error 'npn-image-form__field--needs-attention'}}"
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

    <textarea
      id={{@fieldId}}
      aria-invalid={{if @error "true"}}
      {{on "input" @onInput}}
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
</template>;

export default NpnField;
