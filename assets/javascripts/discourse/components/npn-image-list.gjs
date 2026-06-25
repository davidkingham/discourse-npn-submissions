import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import lightbox from "discourse/lib/lightbox";
import { eq } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import NpnLargeImageWarning from "./npn-large-image-warning";
import NpnUploadZone from "./npn-upload-zone";

// Tag the active PhotoSwipe root so our scoped CSS can trim the toolbar to just
// the close button — and only for our thumbnail previews, never cooked-post
// image lightboxes. window.pswp is set by photoswipe-lightbox on open and
// removed on close, so the class is gone automatically when the lightbox closes.
function tagNpnLightboxRoot(tries = 0) {
  const root = window.pswp?.element;
  if (root) {
    root.classList.add("npn-thumb-lightbox");
  } else if (tries < 30) {
    requestAnimationFrame(() => tagNpnLightboxRoot(tries + 1));
  }
}

// Reusable ordered image list: upload (click or drag-drop from desktop),
// thumbnails, drag-to-reorder (and up/down buttons), an optional per-image note,
// and an optional "Main" or numbered badge.
//
// Controlled component: the parent owns the images array and the upload function.
//   @images        - [{ upload, note }] (required)
//   @onChange      - (nextImages) => void (required)
//   @uploadFile    - (file) => Promise<upload|null> (required; parent owns `uploading`)
//   @uploading     - bool (shows the "Uploading…" hint, disables the add zone)
//   @maxImages     - number
//   @accept        - file accept (default "image/*")
//   @multiple      - allow selecting several files at once (default true)
//   @uploadLabel   - drop-zone prompt
//   @enableNotes   - show the per-image note input
//   @notePlaceholder
//   @badge         - "main" | "number" | null
//   @mainBadgeText - text for the "main" badge
//   @numberLabel   - word before the index for the "number" badge (e.g. "Image")
//   @showLargeImageWarning - opt-in: show a per-image over-threshold notice for
//                    member photos. Leave off for screenshots/diagnostic lists.
export default class NpnImageList extends Component {
  @tracked dragIndex = null;
  @tracked dropSlot = null;
  // Set when a selection exceeds the maximum so the user is told their extra
  // files were dropped, instead of them silently disappearing.
  @tracked limitNotice = null;
  // Set when a selection repeated an image already added here or in a sibling
  // list (e.g. the same file in project images and alternates).
  @tracked duplicateNotice = null;

  // Thumbnail anchors whose core (PhotoSwipe) lightbox has been wired. We init
  // lazily on first click so we never preload every image, and so we don't
  // re-enter our own click handler in a loop after re-firing the click.
  _lightboxed = new WeakSet();

  willDestroy() {
    super.willDestroy(...arguments);
    // Close the lightbox if the list is torn down while it's open (e.g. the user
    // navigates away), matching core's cleanup pattern.
    window.pswp?.close();
  }

  get images() {
    return this.args.images ?? [];
  }

  get rows() {
    return this.images.map((entry, index) => ({
      entry,
      index,
      number: index + 1,
    }));
  }

  get maxImages() {
    return this.args.maxImages ?? 1;
  }

  get multiple() {
    return this.args.multiple ?? true;
  }

  get hasMultiple() {
    return this.images.length > 1;
  }

  // When the parent opts in (@singleLarge) and there is exactly one image, show
  // it as a large, uncropped preview instead of a small square thumbnail.
  get isSingleLarge() {
    return !!this.args.singleLarge && this.images.length === 1;
  }

  // Once at least one image exists, switch the dropzone copy to the quieter
  // "add another" label (and show the variations helper) when the parent
  // provides them; the first upload still uses the primary @uploadLabel.
  get zoneLabel() {
    return this.images.length > 0 && this.args.addMoreLabel
      ? this.args.addMoreLabel
      : this.args.uploadLabel;
  }

  get zoneHelp() {
    return this.images.length > 0 ? this.args.addMoreHelp : null;
  }

  get lastIndex() {
    return this.images.length - 1;
  }

  get canAdd() {
    return this.images.length < this.maxImages && !this.args.uploading;
  }

  change(next) {
    this.args.onChange?.(next);
  }

  @action
  async addFiles(files) {
    this.limitNotice = null;
    this.duplicateNotice = null;
    // Upload ids already in use — this list plus any reserved by a sibling list
    // (e.g. project alternates can't repeat a project image). Deduped by id
    // because Discourse returns the same upload for an identical file.
    const taken = new Set([
      ...this.images.map((entry) => entry.upload.id),
      ...(this.args.reservedUploadIds ?? []),
    ]);
    let next = [...this.images];
    let skipped = 0;
    let duplicates = 0;
    for (const file of files) {
      if (next.length >= this.maxImages) {
        // Over the cap — count the rest so we can tell the user rather than
        // dropping them silently.
        skipped += 1;
        continue;
      }
      const upload = await this.args.uploadFile(file);
      if (!upload) {
        continue;
      }
      if (taken.has(upload.id)) {
        // Same file already added here or in the sibling list.
        duplicates += 1;
        continue;
      }
      // The first image added to an empty list is the main/primary image; let
      // the parent react to it (e.g. read EXIF from the original file).
      const isPrimary = next.length === 0;
      next = [...next, { upload, note: "" }];
      taken.add(upload.id);
      this.change(next);
      if (isPrimary) {
        this.args.onPrimaryFile?.(file);
      }
    }
    if (skipped > 0) {
      this.limitNotice = i18n("npn_submissions.form.images.limit_notice", {
        count: this.maxImages,
      });
    }
    if (duplicates > 0) {
      this.duplicateNotice = i18n(
        "npn_submissions.form.images.duplicate_notice",
        {
          count: duplicates,
        }
      );
    }
  }

  @action
  removeImage(index) {
    // Making room dismisses the "couldn't add" notices.
    this.limitNotice = null;
    this.duplicateNotice = null;
    this.change(this.images.filter((_, i) => i !== index));
  }

  // Open the clicked thumbnail in Discourse's core lightbox. On first click we
  // lazily wire the lightbox to just this thumbnail (single image — no grouped
  // dataSource, no preloading the rest of the list), then re-fire the click so
  // core's own handler opens it. Subsequent clicks fall straight through to that
  // handler. The drag handle and the reorder/remove buttons are separate
  // elements, so they never trigger this.
  @action
  async openLightbox(event) {
    const anchor = event.currentTarget;
    if (this._lightboxed.has(anchor)) {
      // Already wired — core's own click handler opens it. Tag the root so our
      // scoped CSS trims the toolbar to just the close button.
      tagNpnLightboxRoot();
      return;
    }
    event.preventDefault();
    await lightbox(anchor.closest(".npn-image-form__thumb"));
    this._lightboxed.add(anchor);
    anchor.click();
  }

  @action
  updateNote(index, event) {
    const note = event.target.value;
    this.change(
      this.images.map((entry, i) => (i === index ? { ...entry, note } : entry))
    );
  }

  @action
  moveUp(index) {
    this.moveImage(index, index - 1);
  }

  @action
  moveDown(index) {
    this.moveImage(index, index + 1);
  }

  moveImage(from, to) {
    if (from == null || to == null || from === to) {
      return;
    }
    if (to < 0 || to >= this.images.length) {
      return;
    }
    const next = [...this.images];
    const [item] = next.splice(from, 1);
    next.splice(to, 0, item);
    this.change(next);
  }

  @action
  onDragStart(index, event) {
    this.dragIndex = index;
    event.dataTransfer.effectAllowed = "move";
    event.dataTransfer.setData("text/plain", String(index));
  }

  @action
  onDragOver(index, event) {
    event.preventDefault();
    event.dataTransfer.dropEffect = "move";
    const rect = event.currentTarget.getBoundingClientRect();
    const inTopHalf = event.clientY < rect.top + rect.height / 2;
    this.dropSlot = inTopHalf ? index : index + 1;
  }

  @action
  onDrop(event) {
    event.preventDefault();
    this.moveToSlot(this.dragIndex, this.dropSlot);
    this.resetDrag();
  }

  @action
  onDragEnd() {
    this.resetDrag();
  }

  resetDrag() {
    this.dragIndex = null;
    this.dropSlot = null;
  }

  moveToSlot(from, slot) {
    if (from == null || slot == null) {
      return;
    }
    const next = [...this.images];
    const [item] = next.splice(from, 1);
    const insertAt = slot > from ? slot - 1 : slot;
    if (insertAt < 0 || insertAt > next.length) {
      return;
    }
    next.splice(insertAt, 0, item);
    this.change(next);
  }

  <template>
    {{#each this.rows key="entry.upload.id" as |row|}}
      <div
        class="npn-image-form__image-row
          {{if this.isSingleLarge 'npn-image-form__image-row--single'}}
          {{if (eq this.dragIndex row.index) 'is-dragging'}}
          {{if (eq this.dropSlot row.index) 'drop-before'}}"
        {{on "dragover" (fn this.onDragOver row.index)}}
        {{on "drop" this.onDrop}}
        {{on "dragend" this.onDragEnd}}
      >
        {{#if this.hasMultiple}}
          <span
            class="npn-image-form__drag-handle"
            draggable="true"
            title={{i18n "npn_submissions.form.images.drag_hint"}}
            {{on "dragstart" (fn this.onDragStart row.index)}}
          >{{dIcon "grip-lines"}}</span>
        {{/if}}

        <div class="npn-image-form__thumb">
          <a
            class="lightbox npn-image-form__thumb-link"
            href={{row.entry.upload.url}}
            rel="nofollow noopener"
            draggable="false"
            aria-label={{i18n "npn_submissions.form.images.view_full"}}
            {{on "click" this.openLightbox}}
          >
            <img
              src={{row.entry.upload.url}}
              alt={{row.entry.upload.original_filename}}
            />
          </a>
          {{#if (eq @badge "number")}}
            <span class="npn-image-form__number-badge">
              {{@numberLabel}}
              {{row.number}}
            </span>
          {{else if (eq @badge "main")}}
            {{#if this.hasMultiple}}
              {{#if (eq row.index 0)}}
                <span
                  class="npn-image-form__main-badge"
                >{{@mainBadgeText}}</span>
              {{/if}}
            {{/if}}
          {{/if}}
        </div>

        {{#if @enableNotes}}
          {{#if @noteLabel}}
            {{! A small visible label above a compact, growable textarea — used
            where the hint is too long for a single-line placeholder. }}
            <label class="npn-image-form__note">
              <span class="npn-image-form__note-label">{{@noteLabel}}</span>
              <textarea
                class="npn-image-form__note-input"
                rows="2"
                placeholder={{@notePlaceholder}}
                value={{row.entry.note}}
                {{on "input" (fn this.updateNote row.index)}}
              ></textarea>
            </label>
          {{else}}
            <input
              type="text"
              aria-label={{@notePlaceholder}}
              placeholder={{@notePlaceholder}}
              value={{row.entry.note}}
              {{on "input" (fn this.updateNote row.index)}}
            />
          {{/if}}
        {{/if}}

        {{#if this.hasMultiple}}
          <div class="npn-image-form__reorder">
            <DButton
              @icon="arrow-up"
              @action={{fn this.moveUp row.index}}
              @disabled={{eq row.index 0}}
              @title="npn_submissions.form.images.move_up"
              class="btn-flat"
            />
            <DButton
              @icon="arrow-down"
              @action={{fn this.moveDown row.index}}
              @disabled={{eq row.index this.lastIndex}}
              @title="npn_submissions.form.images.move_down"
              class="btn-flat"
            />
          </div>
        {{/if}}

        <DButton
          @icon="trash-can"
          @label={{if this.isSingleLarge "npn_submissions.form.images.remove"}}
          @title="npn_submissions.form.images.remove"
          @ariaLabel="npn_submissions.form.images.remove"
          @action={{fn this.removeImage row.index}}
          class="btn-flat npn-image-form__remove"
        />

        {{#if @showLargeImageWarning}}
          {{! Last child so it wraps onto its own full-width line below the
          thumbnail and controls, staying tied to this image's card. }}
          <NpnLargeImageWarning @filesize={{row.entry.upload.filesize}} />
        {{/if}}
      </div>
    {{/each}}

    {{#if (eq this.dropSlot this.images.length)}}
      <div class="npn-image-form__drop-line"></div>
    {{/if}}

    {{#if this.canAdd}}
      <NpnUploadZone
        @accept={{if @accept @accept "image/*"}}
        @multiple={{this.multiple}}
        @disabled={{@uploading}}
        @label={{this.zoneLabel}}
        @onFiles={{this.addFiles}}
      />
      {{#if this.zoneHelp}}
        <p class="npn-help npn-image-form__add-more-help">{{this.zoneHelp}}</p>
      {{/if}}
    {{/if}}

    {{#if this.limitNotice}}
      <p
        class="npn-image-form__add-notice"
        role="alert"
      >{{this.limitNotice}}</p>
    {{/if}}

    {{#if this.duplicateNotice}}
      <p
        class="npn-image-form__add-notice"
        role="alert"
      >{{this.duplicateNotice}}</p>
    {{/if}}

    {{#if @uploading}}
      <p class="npn-image-form__uploading">
        {{i18n "npn_submissions.form.uploading"}}
      </p>
    {{/if}}
  </template>
}
