import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DButton from "discourse/ui-kit/d-button";
import DEditor from "discourse/ui-kit/d-editor";
import { i18n } from "discourse-i18n";
import NpnExpandableExample from "./npn-expandable-example";
import NpnPromptChips from "./npn-prompt-chips";
import NpnUploadZone from "./npn-upload-zone";

// A single labelled rich-text field with optional helper text, an expandable
// example, and prompt chips. The writing surface is Discourse's DEditor
// (ProseMirror/WYSIWYG). It is controlled: the parent owns the markdown via
// `@value` and is notified of edits via `@onChange` (DEditor's change event,
// whose `target.value` is the markdown). The stored value stays markdown in
// both WYSIWYG and Markdown sub-modes, so drafts, autosave, preview, and post
// building are unchanged.
//
// @mention/#hashtag/:emoji autocomplete and link insertion are provided
// natively by DEditor (scoped by `@categoryId`). An image-upload button is
// added to the toolbar via `@extraButtons`: the bare DEditor has no upload
// pipeline of its own, so we POST to /uploads.json (the same endpoint the
// forms' image uploads use) and insert the `![](upload://…)` markdown through
// DEditor's unified TextManipulation (captured via `@onSetup`), which works in
// both WYSIWYG and Markdown sub-modes. The formatting toolbar (DEditor's button
// bar, which also carries the Markdown/WYSIWYG switch) is hidden by default to
// keep the surface calm; the "Aa" toggle reveals it.
//
// When `@withMetadata` is set (Technical Details) the field also offers, above
// the editor: an opt-in "use photo metadata" helper (when EXIF was read from
// the main image) and quick templates; and below it: the examples and a
// collapsed "upload a metadata screenshot instead" fallback. The editor is
// always shown — typed text and/or a screenshot both satisfy the backend's
// "text OR screenshot" rule, so there is no method selector.
//
// `@compact` shortens the default editor height so optional fields read as
// quieter context next to the page's primary required field (see
// .npn-image-form__field--compact in the stylesheet).
export default class NpnField extends Component {
  @tracked toolbarOpen = false;

  // DEditor's unified TextManipulation for the current sub-mode (re-handed on
  // every WYSIWYG<->Markdown toggle), used to insert uploaded-image markdown.
  #textManipulation = null;
  // Hidden <input type="file"> the upload toolbar button opens.
  #fileInput = null;

  @action
  toggleToolbar() {
    this.toolbarOpen = !this.toolbarOpen;
  }

  // Capture DEditor's TextManipulation so the upload button can insert at the
  // caret. Returns no destructor; DEditor tears its own copy down on re-setup.
  @action
  setupEditor(textManipulation) {
    this.#textManipulation = textManipulation;
  }

  @action
  captureFileInput(element) {
    this.#fileInput = element;
  }

  // Register an image-upload button on DEditor's toolbar. Lives in the same
  // "insertions" group the composer uses for its upload button.
  @action
  addUploadButton(toolbar) {
    toolbar.addButton({
      id: "npn-upload",
      group: "insertions",
      icon: "upload",
      title: "npn_submissions.form.toolbar.upload",
      action: () => this.#fileInput?.click(),
    });
  }

  // Upload the chosen image to the shared /uploads.json endpoint and insert its
  // markdown at the caret. A placeholder is inserted first so the user sees
  // progress and the final markdown lands where they clicked, even though the
  // upload is async.
  @action
  async onUploadFiles(event) {
    const file = event.target.files?.[0];
    // Reset so picking the same file again still fires `change`.
    event.target.value = "";
    if (!file || !this.#textManipulation) {
      return;
    }

    const placeholder = `[${i18n("npn_submissions.form.toolbar.uploading")}]()`;
    const selected = this.#textManipulation.getSelected();
    this.#textManipulation.addText(selected, placeholder);

    try {
      const formData = new FormData();
      formData.append("upload_type", "composer");
      formData.append("file", file);
      const upload = await ajax("/uploads.json", {
        type: "POST",
        data: formData,
        processData: false,
        contentType: false,
      });
      const url = upload.short_url || upload.url;
      const dimensions =
        upload.width && upload.height
          ? `|${upload.width}x${upload.height}`
          : "";
      const markdown = `![${upload.original_filename}${dimensions}](${url})`;
      this.#textManipulation.replaceText(placeholder, markdown);
    } catch (e) {
      // Drop the placeholder so a failed upload leaves no stray text.
      this.#textManipulation.replaceText(placeholder, "");
      popupAjaxError(e);
    }
  }

  // Tooltip + aria-label for the icon-only formatting toggle; flips to a "hide"
  // phrasing while the toolbar is open so it reads correctly to pointer and
  // screen-reader users alike.
  get toolbarToggleLabel() {
    return i18n(
      this.toolbarOpen
        ? "npn_submissions.form.toolbar.formatting_hide"
        : "npn_submissions.form.toolbar.formatting_show"
    );
  }

  <template>
    <div
      class="npn-image-form__field
        {{if @error 'npn-image-form__field--needs-attention'}}
        {{if @compact 'npn-image-form__field--compact'}}"
    >
      <label for={{@fieldId}}>
        {{@label}}
        {{#if @required}}
          <span class="npn-required">{{i18n
              "npn_submissions.form.required"
            }}</span>
        {{else if @optional}}
          <span class="npn-optional">{{i18n
              "npn_submissions.form.optional"
            }}</span>
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
              >{{i18n
                  "npn_submissions.form.photo_metadata.insert_again"
                }}</button>
            {{else}}
              <p class="npn-photo-metadata__title">
                {{i18n "npn_submissions.form.photo_metadata.found"}}
              </p>
              <p class="npn-photo-metadata__help">
                {{i18n "npn_submissions.form.photo_metadata.found_help"}}
              </p>
              <DButton
                @translatedLabel={{i18n
                  "npn_submissions.form.photo_metadata.use"
                }}
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
                  (i18n
                    "npn_submissions.form.technical_templates.basic_exif.body"
                  )
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

      {{! Formatting toolbar is hidden by default to keep the writing surface
      calm; the "Aa" toggle reveals DEditor's button bar (which also carries the
      built-in Markdown/WYSIWYG switch). Link insertion and @mention/#hashtag
      autocomplete are provided natively by DEditor, so there is no custom
      Insert-link button. }}
      <div
        class="npn-field__toolbar"
        role="toolbar"
        aria-label={{i18n "npn_submissions.form.toolbar.label"}}
      >
        <DButton
          @icon="font"
          @translatedTitle={{this.toolbarToggleLabel}}
          @translatedAriaLabel={{this.toolbarToggleLabel}}
          @action={{this.toggleToolbar}}
          aria-pressed={{if this.toolbarOpen "true" "false"}}
          class="btn-flat btn-small npn-field__format-toggle
            {{if this.toolbarOpen '--active'}}"
        />
      </div>

      <div
        class="npn-field__editor-wrap {{if this.toolbarOpen '--toolbar-open'}}"
      >
        <DEditor
          @value={{@value}}
          @change={{@onChange}}
          @onSetup={{this.setupEditor}}
          @extraButtons={{this.addUploadButton}}
          @categoryId={{@categoryId}}
          @disabled={{@disabled}}
          @showLink={{true}}
          @textAreaId={{@fieldId}}
          class="npn-field__editor"
        />
        {{! Hidden picker the toolbar upload button opens. }}
        <input
          type="file"
          accept="image/*"
          class="npn-field__upload-input"
          {{didInsert this.captureFileInput}}
          {{on "change" this.onUploadFiles}}
        />
      </div>

      {{#if @withMetadata}}
        {{! Examples sit below the textarea as supporting guidance. }}
        <NpnExpandableExample
          @summary={{i18n "npn_submissions.form.technical_examples.summary"}}
        >
          <ul class="npn-image-form__specs">
            <li>{{i18n "npn_submissions.form.technical_examples.camera"}}</li>
            <li>{{i18n "npn_submissions.form.technical_examples.lens"}}</li>
            <li>{{i18n "npn_submissions.form.technical_examples.field"}}</li>
            <li>{{i18n
                "npn_submissions.form.technical_examples.processing"
              }}</li>
          </ul>
        </NpnExpandableExample>

        {{! Metadata screenshot: shown directly once uploaded; otherwise a quiet,
        collapsed fallback for when EXIF was stripped or is incomplete. }}
        {{#if @metadataUpload}}
          <div class="npn-field__metadata">
            <label>{{i18n
                "npn_submissions.form.metadata_screenshot.label"
              }}</label>
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
                {{i18n
                  "npn_submissions.form.metadata_screenshot.fallback_help"
                }}
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
