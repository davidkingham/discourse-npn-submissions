import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { eq } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import {
  buildSequenceMarkup,
  formatShorthand,
  numberLabel,
  parseShorthand,
  sheetDisplaySize,
} from "../lib/npn-sequence";
import { createSequenceSheet } from "../lib/npn-sequence-sheet";

// The post-sized optimized rendition when available — much lighter than the
// original for a thumbnail.
const thumbSrc = (image) => image?.sheet_url || image?.url;
const inc = (n) => n + 1;
const dec = (n) => n - 1;

// Suggest-a-Sequence builder. Shows the project's numbered images and lets a
// critic (or the photographer) arrange a proposed order — by dragging, by the
// ←/→/× buttons, by tapping images in the tray, or by typing "1, 3, 4, A1" —
// then hands back an [npn-sequence] block via `@onInsert(markup)`.
//
// A plain component (not a modal) so it can be embedded inline in places that
// are already a modal — the critique workspace is one, and Discourse shows
// only one modal at a time. The reply composer wraps it in
// NpnSequenceBuilderModal.
//
// @images    { originals: [...], alternates: [...] } from topic.npn_project_images
// @initial   optional { label, numbers } to reopen an existing block
// @onInsert  (markup) => void
// @onCancel  () => void
export default class NpnSequenceBuilder extends Component {
  @tracked sequence;
  @tracked label;
  @tracked shorthand;
  @tracked shorthandProblems = null;
  @tracked dragIndex = null;
  @tracked dropSlot = null;
  @tracked inserting = false;
  @tracked insertError = null;

  constructor() {
    super(...arguments);
    const initial = this.args.initial;
    const known = this.knownNumbers;
    const start = initial?.numbers?.filter((n) => known.has(n));
    this.sequence = start?.length ? start : this.originalNumbers;
    this.label = initial?.label ?? "";
    this.shorthand = formatShorthand(this.sequence);
  }

  get originals() {
    return this.args.images?.originals ?? [];
  }

  get alternates() {
    return this.args.images?.alternates ?? [];
  }

  get allImages() {
    return [...this.originals, ...this.alternates];
  }

  get byNumber() {
    return new Map(this.allImages.map((image) => [image.number, image]));
  }

  get knownNumbers() {
    return new Set(this.allImages.map((image) => image.number));
  }

  get originalNumbers() {
    return this.originals.map((image) => image.number);
  }

  get isEditing() {
    return !!this.args.initial;
  }

  get sequenceTiles() {
    const byNumber = this.byNumber;
    const last = this.sequence.length - 1;
    return this.sequence
      .map((number, index) => ({
        index,
        image: byNumber.get(number),
        src: thumbSrc(byNumber.get(number)),
        label: numberLabel(number),
        isAlternate: number.startsWith("A"),
        isFirst: index === 0,
        isLast: index === last,
        // Moved = an original that isn't at its submitted position.
        moved: !number.startsWith("A") && number !== String(index + 1),
      }))
      .filter((tile) => tile.image);
  }

  get trayTiles() {
    const inSequence = new Set(this.sequence);
    return this.allImages
      .filter((image) => !inSequence.has(image.number))
      .map((image) => ({
        image,
        src: thumbSrc(image),
        label: numberLabel(image.number),
        isAlternate: image.number.startsWith("A"),
      }));
  }

  get originalTiles() {
    return this.originals.map((image) => ({
      image,
      src: thumbSrc(image),
      label: numberLabel(image.number),
    }));
  }

  get canInsert() {
    return this.sequence.length > 0;
  }

  get insertDisabled() {
    return !this.canInsert || this.inserting;
  }

  get insertLabel() {
    if (this.inserting) {
      return "npn_submissions.sequence.creating";
    }
    return this.isEditing
      ? "npn_submissions.sequence.update"
      : "npn_submissions.sequence.insert";
  }

  setSequence(next) {
    this.sequence = next;
    this.shorthand = formatShorthand(next);
    this.shorthandProblems = null;
  }

  @action
  onShorthandInput(event) {
    this.shorthand = event.target.value;
    const { numbers, invalid, unknown } = parseShorthand(
      this.shorthand,
      this.knownNumbers
    );
    this.sequence = numbers;
    const problems = [];
    if (invalid.length) {
      problems.push(
        i18n("npn_submissions.sequence.shorthand_invalid", {
          tokens: invalid.join(", "),
        })
      );
    }
    if (unknown.length) {
      problems.push(
        i18n("npn_submissions.sequence.shorthand_unknown", {
          tokens: unknown.join(", "),
        })
      );
    }
    this.shorthandProblems = problems.length ? problems.join(" · ") : null;
  }

  @action
  onShorthandBlur() {
    // Normalize what was typed ("a1 3,4" → "A1, 3, 4") once the critic leaves
    // the field, but keep any problem message visible.
    const problems = this.shorthandProblems;
    this.shorthand = formatShorthand(this.sequence);
    this.shorthandProblems = problems;
  }

  @action
  onLabelInput(event) {
    this.label = event.target.value;
  }

  @action
  add(number) {
    this.setSequence([...this.sequence, number]);
  }

  @action
  remove(index) {
    this.setSequence(this.sequence.filter((_, i) => i !== index));
  }

  @action
  move(from, to) {
    if (to < 0 || to >= this.sequence.length || from === to) {
      return;
    }
    const next = [...this.sequence];
    const [item] = next.splice(from, 1);
    next.splice(to, 0, item);
    this.setSequence(next);
  }

  @action
  reset() {
    this.setSequence(this.originalNumbers);
  }

  @action
  clear() {
    this.setSequence([]);
  }

  // Horizontal drag-to-reorder (tiles flow left→right, wrapping). Mirrors the
  // vertical logic in npn-image-list: hovering the left half of a tile targets
  // the slot before it, the right half the slot after it.
  @action
  onDragStart(index, event) {
    this.dragIndex = index;
    event.dataTransfer.effectAllowed = "move";
    event.dataTransfer.setData("text/plain", String(index));
  }

  @action
  onDragOver(index, event) {
    if (this.dragIndex == null) {
      return;
    }
    event.preventDefault();
    event.dataTransfer.dropEffect = "move";
    const rect = event.currentTarget.getBoundingClientRect();
    const inLeftHalf = event.clientX < rect.left + rect.width / 2;
    this.dropSlot = inLeftHalf ? index : index + 1;
  }

  @action
  onDrop(event) {
    event.preventDefault();
    const from = this.dragIndex;
    const slot = this.dropSlot;
    this.resetDrag();
    if (from == null || slot == null) {
      return;
    }
    const insertAt = slot > from ? slot - 1 : slot;
    this.move(from, insertAt);
  }

  @action
  resetDrag() {
    this.dragIndex = null;
    this.dropSlot = null;
  }

  // Draws the sequence as one contact-sheet image, uploads it, and hands the
  // caller an [npn-sequence] block referencing it. Takes a moment, so the
  // button shows progress; on failure the builder stays open with a message
  // and nothing is inserted.
  @action
  async insert() {
    if (!this.canInsert || this.inserting) {
      return;
    }
    const byNumber = this.byNumber;
    const images = this.sequence
      .map((number) => byNumber.get(number))
      .filter(Boolean);
    const numbers = images.map((image) => image.number);

    this.inserting = true;
    this.insertError = null;
    let markup;
    try {
      const sheet = await createSequenceSheet({ images, label: this.label });
      markup = buildSequenceMarkup({
        label: this.label,
        numbers,
        image: {
          short_url: sheet.upload.short_url,
          ...sheetDisplaySize(sheet.width, sheet.height),
        },
      });
    } catch (e) {
      // eslint-disable-next-line no-console
      console.error("[npn-submissions] sequence sheet failed", e);
      if (!this.isDestroying && !this.isDestroyed) {
        this.insertError = i18n("npn_submissions.sequence.create_failed");
        this.inserting = false;
      }
      return;
    }
    this.inserting = false;
    this.args.onInsert?.(markup);
  }

  <template>
    <div class="npn-sequence-builder">
        <p class="npn-sequence-builder__intro">
          {{i18n "npn_submissions.sequence.builder_intro"}}
        </p>

        <section class="npn-sequence-builder__section --original">
          <h3>{{i18n "npn_submissions.sequence.original_heading"}}</h3>
          <div class="npn-sequence-builder__row --reference">
            {{#each this.originalTiles as |tile|}}
              <div class="npn-sequence-builder__tile">
                <span class="npn-sequence-builder__number">{{tile.label}}</span>
                <img src={{tile.src}} alt={{tile.label}} loading="lazy" />
              </div>
            {{/each}}
          </div>
        </section>

        <section class="npn-sequence-builder__section --sequence">
          <div class="npn-sequence-builder__section-head">
            <h3>{{i18n "npn_submissions.sequence.sequence_heading"}}</h3>
            <div class="npn-sequence-builder__section-actions">
              <DButton
                @action={{this.reset}}
                @label="npn_submissions.sequence.reset"
                class="btn-flat btn-small"
              />
              <DButton
                @action={{this.clear}}
                @label="npn_submissions.sequence.clear"
                class="btn-flat btn-small"
              />
            </div>
          </div>

          <label class="npn-sequence-builder__field">
            <span>{{i18n "npn_submissions.sequence.shorthand_label"}}</span>
            <input
              type="text"
              class="npn-sequence-builder__shorthand"
              value={{this.shorthand}}
              placeholder={{i18n
                "npn_submissions.sequence.shorthand_placeholder"
              }}
              autocomplete="off"
              {{on "input" this.onShorthandInput}}
              {{on "blur" this.onShorthandBlur}}
            />
          </label>
          {{#if this.shorthandProblems}}
            <p class="npn-sequence-builder__problem">
              {{this.shorthandProblems}}
            </p>
          {{/if}}

          {{#if this.sequenceTiles.length}}
            <div
              class="npn-sequence-builder__row --sequence"
              {{on "drop" this.onDrop}}
            >
              {{#each this.sequenceTiles as |tile|}}
                <div
                  class="npn-sequence-builder__tile
                    {{if tile.isAlternate 'is-alternate'}}
                    {{if tile.moved 'is-moved'}}
                    {{if (eq this.dragIndex tile.index) 'is-dragging'}}
                    {{if (eq this.dropSlot tile.index) 'drop-before'}}"
                  draggable="true"
                  title={{i18n "npn_submissions.sequence.drag_hint"}}
                  {{on "dragstart" (fn this.onDragStart tile.index)}}
                  {{on "dragover" (fn this.onDragOver tile.index)}}
                  {{on "dragend" this.resetDrag}}
                >
                  <span class="npn-sequence-builder__number">
                    {{tile.label}}
                  </span>
                  <img
                    src={{tile.src}}
                    alt={{tile.label}}
                    draggable="false"
                  />
                  <div class="npn-sequence-builder__controls">
                    <DButton
                      @action={{fn this.move tile.index (dec tile.index)}}
                      @icon="arrow-left"
                      @title="npn_submissions.sequence.move_earlier"
                      @disabled={{tile.isFirst}}
                      class="btn-flat btn-small"
                    />
                    <DButton
                      @action={{fn this.remove tile.index}}
                      @icon="xmark"
                      @title="npn_submissions.sequence.remove"
                      class="btn-flat btn-small"
                    />
                    <DButton
                      @action={{fn this.move tile.index (inc tile.index)}}
                      @icon="arrow-right"
                      @title="npn_submissions.sequence.move_later"
                      @disabled={{tile.isLast}}
                      class="btn-flat btn-small"
                    />
                  </div>
                </div>
              {{/each}}
            </div>
          {{else}}
            <p class="npn-sequence-builder__empty">
              {{i18n "npn_submissions.sequence.empty_sequence"}}
            </p>
          {{/if}}
        </section>

        <section class="npn-sequence-builder__section --tray">
          <h3>{{i18n "npn_submissions.sequence.tray_heading"}}</h3>
          {{#if this.trayTiles.length}}
            <p class="npn-sequence-builder__hint">
              {{i18n "npn_submissions.sequence.tray_hint"}}
            </p>
            <div class="npn-sequence-builder__row --tray">
              {{#each this.trayTiles as |tile|}}
                <button
                  type="button"
                  class="npn-sequence-builder__tile --addable
                    {{if tile.isAlternate 'is-alternate'}}"
                  title={{i18n "npn_submissions.sequence.add" label=tile.label}}
                  {{on "click" (fn this.add tile.image.number)}}
                >
                  <span class="npn-sequence-builder__number">
                    {{tile.label}}
                  </span>
                  <img src={{tile.src}} alt={{tile.label}} />
                </button>
              {{/each}}
            </div>
          {{else}}
            <p class="npn-sequence-builder__empty">
              {{i18n "npn_submissions.sequence.tray_empty"}}
            </p>
          {{/if}}
        </section>

        <label class="npn-sequence-builder__field">
          <span>{{i18n "npn_submissions.sequence.label_label"}}</span>
          <input
            type="text"
            maxlength="80"
            value={{this.label}}
            placeholder={{i18n "npn_submissions.sequence.label_placeholder"}}
            {{on "input" this.onLabelInput}}
          />
        </label>
        {{#if this.insertError}}
          <p class="npn-sequence-builder__problem" role="alert">
            {{this.insertError}}
          </p>
        {{/if}}
        <div class="npn-sequence-builder__actions">
        <DButton
          @action={{this.insert}}
          @label={{this.insertLabel}}
          @disabled={{this.insertDisabled}}
          class="btn-primary"
        />
        <DButton
          @action={{@onCancel}}
          @label="cancel"
          class="btn-flat"
        />
        </div>
    </div>
  </template>
}
