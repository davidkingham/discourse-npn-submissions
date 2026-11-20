import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import { createSuggestionImage } from "../lib/npn-hang-image";
import {
  buildSuggestionMarkup,
  RANKS,
  suggestionKind,
  suggestionSummary,
} from "../lib/npn-hang-suggestion";
import {
  formatShorthand,
  numberLabel,
  parseShorthand,
  sheetDisplaySize,
} from "../lib/npn-sequence";
import { resolveHang } from "../lib/npn-wall-layout";
import NpnHangEditor from "./npn-hang-editor";

const thumbSrc = (image) => image?.sheet_url || image?.url;

function projectIndex(number) {
  const alt = number.startsWith("A");
  return (alt ? 1000 : 0) + parseInt(number.replace("A", ""), 10);
}

// "Suggest a hang": a critic's answer to the photographer's hang, built on
// the same wall. It starts from the photographer's hang (order, sizes,
// look); the critic can
//   - reorder (select a print and move it, or type "9, 8, 7, 5"),
//   - leave prints out (they drop into a "Left out" strip),
//   - bring in alternates,
//   - mark prints strongest ★ / keep ✓ / unsure ?,
//   - for a show or web gallery, change the layout, look and sizes,
// and "Add to critique" draws it as one wall image (with marks and the
// left-out strip) and hands back the image line via @onInsert.
//
// The wording and tools follow the project's presentation goal: a book or
// magazine gets a "sequence" (no look), a LensWork / On Landscape
// submission a "selection" (no order: the publisher sequences it).
//
// A plain component (not a modal) so the critique workspace — itself a
// modal — can embed it; the reply composer wraps it in a modal.
//
// @images   topic.npn_project_images
// @initial  optional { label, order, ranks, layout } (reopening a suggestion)
// @state    optional saved work in progress { label, order, ranks, hang }
// @onStateChange (state) => void — for drafts
// @onInsert (markup, label) => void
// @onCancel () => void
export default class NpnHangSuggester extends Component {
  @service("npn-sequence-builder") builder;

  @tracked order;
  @tracked ranks;
  @tracked label;
  @tracked hang;
  @tracked shorthand;
  @tracked shorthandProblems = null;
  @tracked selectedNumbers = [];
  @tracked inserting = false;
  @tracked insertError = null;

  constructor() {
    super(...arguments);
    const known = this.knownNumbers;
    const state = this.args.initial ?? this.args.state;
    const order = (state?.order ?? []).filter((n) => known.has(n));
    // No work in progress: start from the proposed order the critic was
    // looking at on the post, if any, else the main order.
    const viewed = state
      ? []
      : (this.builder.viewedOrderFor(this.images) ?? []).filter((n) =>
          known.has(n)
        );
    this.order = order.length
      ? order
      : viewed.length
        ? viewed
        : this.originalNumbers;
    this.ranks = { ...(state?.ranks ?? {}) };
    this.label = state?.label ?? "";
    this.hang =
      this.args.state && !this.args.initial
        ? (this.args.state.hang ?? null)
        : state?.layout
          ? { ...(this.photographerHang ?? {}), layout: state.layout }
          : state?.book
            ? this.hangFromBook(state.book, this.order)
            : null;
    this.shorthand = formatShorthand(this.order);
  }

  get images() {
    return this.args.images ?? {};
  }

  get originals() {
    return this.images.originals ?? [];
  }

  get alternates() {
    return this.images.alternates ?? [];
  }

  get intent() {
    return this.images.intent ?? null;
  }

  // The goal the tool works in: the photographer's own, so a book's critics
  // plan spreads (pairs, across both pages, the cover) on the same pages.
  get toolIntent() {
    return this.intent;
  }

  // Every image a cover may come from: what's hung plus the alternates.
  get coverPool() {
    return [...this.prints, ...this.alternates];
  }

  // A reopened spreads suggestion ({ facing, across, left, cover } in print
  // numbers) as a saved hang, on top of the photographer's look.
  hangFromBook(book, order) {
    const byNumber = this.byNumber;
    const id = (number) => byNumber.get(number)?.upload_id;
    const facing = new Map((book.facing ?? []).map((pair) => [pair[0], pair]));
    const second = new Set((book.facing ?? []).map((pair) => pair[1]));
    const spreads = [];
    order.forEach((number) => {
      if (second.has(number)) {
        return;
      }
      if (facing.has(number)) {
        spreads.push({ ids: facing.get(number).map(id) });
      } else {
        spreads.push({
          ids: [id(number)],
          side: (book.across ?? []).includes(number)
            ? "full"
            : (book.left ?? []).includes(number)
              ? "left"
              : "right",
        });
      }
    });
    return {
      ...(this.photographerHang ?? {}),
      spreads,
      cover: book.cover ? (id(book.cover) ?? null) : null,
    };
  }

  // The resolved book as the alt text describes it, in print numbers.
  bookSummary(resolved, prints) {
    const number = (i) => prints[i].number;
    const singles = (side) =>
      resolved.spreads
        .filter((s) => s.indexes.length === 1 && s.side === side)
        .map((s) => number(s.indexes[0]));
    return {
      facing: resolved.spreads
        .filter((s) => s.indexes.length === 2)
        .map((s) => s.indexes.map(number)),
      across: singles("full"),
      left: singles("left"),
      cover: resolved.coverImage?.number ?? null,
    };
  }

  get kind() {
    return suggestionKind(this.intent);
  }

  get isSelection() {
    return this.kind === "selection";
  }

  get photographerHang() {
    return this.images.hang ?? null;
  }

  get byNumber() {
    return new Map(
      [...this.originals, ...this.alternates].map((image) => [
        image.number,
        image,
      ])
    );
  }

  get knownNumbers() {
    return new Set(this.byNumber.keys());
  }

  get originalNumbers() {
    return this.originals.map((image) => image.number);
  }

  get prints() {
    const byNumber = this.byNumber;
    return this.order.map((number) => byNumber.get(number)).filter(Boolean);
  }

  get currentHang() {
    return this.hang ?? this.photographerHang;
  }

  get leftOutTiles() {
    const hung = new Set(this.order);
    return this.originals
      .filter((image) => !hung.has(image.number))
      .map((image) => ({
        image,
        number: image.number,
        src: thumbSrc(image),
        label: numberLabel(image.number),
      }));
  }

  get alternateTiles() {
    const hung = new Set(this.order);
    return this.alternates
      .filter((image) => !hung.has(image.number))
      .map((image) => ({
        image,
        number: image.number,
        src: thumbSrc(image),
        label: numberLabel(image.number),
      }));
  }

  get marks() {
    return this.ranks;
  }

  get introKey() {
    return `npn_submissions.suggest.intro.${this.kind}`;
  }

  get hasSelection() {
    return this.selectedNumbers.length > 0;
  }

  get selectionLabel() {
    const numbers = this.selectedNumbers;
    return numbers.length === 1
      ? numberLabel(numbers[0])
      : i18n("npn_submissions.suggest.selected_many", {
          count: numbers.length,
        });
  }

  get rankButtons() {
    const selected = this.selectedNumbers;
    return RANKS.map((rank) => ({
      key: rank.key,
      symbol: rank.symbol,
      label: i18n(`npn_submissions.suggest.ranks.${rank.key}`),
      active:
        selected.length > 0 &&
        selected.every((n) => this.ranks[n] === rank.key),
    }));
  }

  get canMove() {
    return !this.isSelection && this.selectedNumbers.length === 1;
  }

  // Something to suggest: a different order or set, a mark, or a changed
  // hang. (A reopened suggestion can always be updated.)
  get hasChanges() {
    return (
      !!this.args.initial ||
      !!this.hang ||
      Object.keys(this.ranks).length > 0 ||
      this.order.join(",") !== this.originalNumbers.join(",")
    );
  }

  get canInsert() {
    return this.order.length > 0 && this.hasChanges && !this.inserting;
  }

  get insertLabel() {
    if (this.inserting) {
      return "npn_submissions.suggest.creating";
    }
    return this.args.initial
      ? "npn_submissions.suggest.update"
      : "npn_submissions.suggest.insert";
  }

  // --- state -------------------------------------------------------------

  // Saved as the critic's work in progress — but not while an earlier
  // suggestion is reopened for editing, which would overwrite that work
  // (the reopened one carries no sizes or look).
  emitState() {
    if (this.args.initial) {
      return;
    }
    this.args.onStateChange?.({
      label: this.label,
      order: this.order,
      ranks: this.ranks,
      hang: this.hang,
    });
  }

  setOrder(next) {
    this.order = next;
    this.shorthand = formatShorthand(next);
    this.shorthandProblems = null;
    // Marks only make sense on prints that are hung.
    const hung = new Set(next);
    this.ranks = Object.fromEntries(
      Object.entries(this.ranks).filter(([n]) => hung.has(n))
    );
    this.selectedNumbers = this.selectedNumbers.filter((n) => hung.has(n));
    this.emitState();
  }

  @action
  setHang(next) {
    this.hang = next;
    this.emitState();
  }

  @action
  setSelected(numbers) {
    this.selectedNumbers = numbers;
  }

  @action
  onLabelInput(event) {
    this.label = event.target.value;
    this.emitState();
  }

  @action
  onShorthandInput(event) {
    this.shorthand = event.target.value;
    const { numbers, invalid, unknown } = parseShorthand(
      this.shorthand,
      this.knownNumbers
    );
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
    if (numbers.length) {
      const typed = this.shorthand;
      this.setOrder(numbers);
      this.shorthand = typed;
    }
    this.shorthandProblems = problems.length ? problems.join(" · ") : null;
  }

  @action
  onShorthandBlur() {
    const problems = this.shorthandProblems;
    this.shorthand = formatShorthand(this.order);
    this.shorthandProblems = problems;
  }

  @action
  setRank(key) {
    const numbers = this.selectedNumbers;
    const allHave = numbers.every((n) => this.ranks[n] === key);
    const next = { ...this.ranks };
    numbers.forEach((n) => {
      if (allHave) {
        delete next[n];
      } else {
        next[n] = key;
      }
    });
    this.ranks = next;
    this.emitState();
  }

  @action
  leaveOut() {
    const out = new Set(this.selectedNumbers);
    this.setOrder(this.order.filter((n) => !out.has(n)));
  }

  @action
  move(direction) {
    const [number] = this.selectedNumbers;
    const from = this.order.indexOf(number);
    const to = from + direction;
    if (from < 0 || to < 0 || to >= this.order.length) {
      return;
    }
    const next = [...this.order];
    next.splice(from, 1);
    next.splice(to, 0, number);
    this.setOrder(next);
  }

  // Hang a left-out print again, or bring in an alternate. In a selection
  // (no order) it goes back to its project position; otherwise at the end.
  @action
  hangPrint(number) {
    if (this.isSelection) {
      this.setOrder(
        [...this.order, number].sort(
          (a, b) => projectIndex(a) - projectIndex(b)
        )
      );
    } else {
      this.setOrder([...this.order, number]);
    }
  }

  @action
  resetToPhotographer() {
    this.hang = null;
    this.ranks = {};
    this.selectedNumbers = [];
    this.setOrder(this.originalNumbers);
  }

  @action
  async insert() {
    if (!this.canInsert) {
      return;
    }
    this.inserting = true;
    this.insertError = null;
    try {
      const prints = this.prints;
      const resolved = resolveHang(
        this.currentHang,
        this.toolIntent,
        prints,
        this.coverPool
      );
      const original = resolveHang(
        this.photographerHang,
        this.toolIntent,
        this.originals
      );
      const hung = new Set(this.order);
      const marks = Object.fromEntries(
        Object.entries(this.ranks).filter(([n]) => hung.has(n))
      );
      const sheet = await createSuggestionImage({
        images: prints,
        hang: resolved,
        marks,
        leftOut: this.leftOutTiles.map((tile) => tile.image),
        title: this.label,
        leftOutLabel: i18n("npn_submissions.suggest.left_out"),
        coverLabel: i18n("npn_submissions.book.cover"),
      });
      const summary = suggestionSummary({
        kind: this.kind,
        order: this.order,
        ranks: marks,
        originals: this.originalNumbers,
        layout: resolved.layout,
        layoutChanged: resolved.layout !== original.layout,
        book:
          this.kind === "spreads" ? this.bookSummary(resolved, prints) : null,
      });
      const markup = buildSuggestionMarkup({
        kind: this.kind,
        label: this.label,
        summary,
        image: {
          short_url: sheet.upload.short_url,
          ...sheetDisplaySize(sheet.width, sheet.height),
        },
      });
      this.args.onInsert?.(markup, this.label);
    } catch (e) {
      // eslint-disable-next-line no-console
      console.error("[npn-submissions] suggest a hang:", e);
      this.insertError = i18n("npn_submissions.suggest.failed");
    } finally {
      if (!this.isDestroying && !this.isDestroyed) {
        this.inserting = false;
      }
    }
  }

  <template>
    <div class="npn-hang-suggester --{{this.kind}}">
      <p class="npn-hang-suggester__intro">{{i18n this.introKey}}</p>

      <div class="npn-hang-suggester__fields">
        <label class="npn-hang-suggester__field">
          <span>{{i18n "npn_submissions.suggest.label"}}</span>
          <input
            type="text"
            value={{this.label}}
            placeholder={{i18n "npn_submissions.suggest.label_placeholder"}}
            {{on "input" this.onLabelInput}}
          />
        </label>
        {{#unless this.isSelection}}
          <label class="npn-hang-suggester__field --order">
            <span>{{i18n "npn_submissions.suggest.order"}}</span>
            <input
              type="text"
              inputmode="text"
              value={{this.shorthand}}
              {{on "input" this.onShorthandInput}}
              {{on "blur" this.onShorthandBlur}}
            />
          </label>
        {{/unless}}
      </div>
      {{#if this.shorthandProblems}}
        <p class="npn-hang-suggester__problem">{{this.shorthandProblems}}</p>
      {{/if}}

      <NpnHangEditor
        @prints={{this.prints}}
        @hang={{this.currentHang}}
        @intent={{this.toolIntent}}
        @alternates={{this.alternates}}
        @marks={{this.marks}}
        @selectedNumbers={{this.selectedNumbers}}
        @onChange={{this.setHang}}
        @onSelectionChange={{this.setSelected}}
      />

      <div class="npn-hang-suggester__toolbar" aria-live="polite">
        {{#if this.hasSelection}}
          <span class="npn-hang-suggester__selection">
            {{this.selectionLabel}}
          </span>
          {{#each this.rankButtons as |rank|}}
            <button
              type="button"
              class="npn-hang-suggester__rank --{{rank.key}}
                {{if rank.active 'is-active'}}"
              aria-pressed={{if rank.active "true" "false"}}
              {{on "click" (fn this.setRank rank.key)}}
            >{{rank.symbol}} {{rank.label}}</button>
          {{/each}}
          <button
            type="button"
            class="npn-hang-suggester__rank --leave-out"
            {{on "click" this.leaveOut}}
          >✕ {{i18n "npn_submissions.suggest.leave_out"}}</button>
          {{#if this.canMove}}
            <DButton
              @action={{fn this.move -1}}
              @icon="arrow-left"
              @title="npn_submissions.suggest.earlier"
              class="btn-default btn-small"
            />
            <DButton
              @action={{fn this.move 1}}
              @icon="arrow-right"
              @title="npn_submissions.suggest.later"
              class="btn-default btn-small"
            />
          {{/if}}
        {{else}}
          <span class="npn-hang-suggester__hint">
            {{i18n "npn_submissions.suggest.hint"}}
          </span>
        {{/if}}
      </div>

      {{#if this.leftOutTiles.length}}
        <section class="npn-hang-suggester__tray">
          <h4>{{i18n "npn_submissions.suggest.left_out"}}</h4>
          <div class="npn-hang-suggester__tiles">
            {{#each this.leftOutTiles as |tile|}}
              <button
                type="button"
                class="npn-hang-suggester__tile --left-out"
                title={{i18n "npn_submissions.suggest.hang_again"}}
                {{on "click" (fn this.hangPrint tile.number)}}
              >
                <img src={{tile.src}} alt={{tile.label}} loading="lazy" />
                <span>{{tile.number}}</span>
              </button>
            {{/each}}
          </div>
        </section>
      {{/if}}

      {{#if this.alternateTiles.length}}
        <section class="npn-hang-suggester__tray">
          <h4>{{i18n "npn_submissions.suggest.alternates"}}</h4>
          <div class="npn-hang-suggester__tiles">
            {{#each this.alternateTiles as |tile|}}
              <button
                type="button"
                class="npn-hang-suggester__tile --alternate"
                title={{i18n "npn_submissions.suggest.bring_in"}}
                {{on "click" (fn this.hangPrint tile.number)}}
              >
                <img src={{tile.src}} alt={{tile.label}} loading="lazy" />
                <span>{{tile.number}}</span>
              </button>
            {{/each}}
          </div>
        </section>
      {{/if}}

      {{#unless this.hasChanges}}
        <p class="npn-hang-suggester__hint">
          {{i18n "npn_submissions.suggest.no_changes"}}
        </p>
      {{/unless}}

      {{#if this.insertError}}
        <p class="npn-hang-suggester__error" role="alert">
          {{this.insertError}}
        </p>
      {{/if}}

      <footer class="npn-hang-suggester__footer">
        <DButton
          @action={{this.resetToPhotographer}}
          @label="npn_submissions.suggest.reset"
          class="btn-flat btn-small"
        />
        <span class="npn-hang-suggester__spacer"></span>
        {{#if @onCancel}}
          <DButton
            @action={{@onCancel}}
            @label="npn_submissions.suggest.cancel"
            class="btn-flat"
          />
        {{/if}}
        <DButton
          @action={{this.insert}}
          @label={{this.insertLabel}}
          @disabled={{if this.canInsert false true}}
          class="btn-primary"
        />
      </footer>
    </div>
  </template>
}
