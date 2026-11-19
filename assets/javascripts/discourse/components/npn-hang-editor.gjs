import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { htmlSafe } from "@ember/template";
import { modifier } from "ember-modifier";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import {
  aspectOf,
  formatPrintSize,
  formatWallWidth,
  FRAMES,
  LAYOUTS,
  layoutWall,
  MAT_WIDTHS,
  MATS,
  PRINT_SIZES,
  resolveHang,
  serializeHang,
  snapSize,
  stepSize,
  WALLS,
} from "../lib/npn-wall-layout";
import NpnHangWall from "./npn-hang-wall";

// Grips are bound with a plain listener (pointerdown is the right event for
// starting a drag; the template lint rule is about click-like handlers).
const gripListener = modifier((element, [callback]) => {
  const handler = (event) => {
    const grip = event.target.closest?.(".npn-hang-wall__grip");
    if (!grip) {
      return;
    }
    const grips = [...element.querySelectorAll(".npn-hang-wall__grip")];
    callback(grips.indexOf(grip), event);
  };
  element.addEventListener("pointerdown", handler);
  return () => element.removeEventListener("pointerdown", handler);
});

// "Hang your show" in the project form: the photographer lays out the prints
// on a wall (one line, rows, or a lead print beside a grid), picks the wall,
// mat and frame, and sizes each print by dragging its corner grip — sizes snap
// to standard print sizes and show live ("16 × 20 in"). A floor line and bench
// give scale; the readout shows how wide the hang is.
//
// Controlled: @hang is the saved hang (server shape) and every change calls
// @onChange(nextHang). Sizes are keyed by upload id so they follow a print
// when it's reordered.
//
// @images   form image entries in order ({ upload: { id, url, width, height } })
// @intent   presentation goal (decides sizing and the starting look)
// @disabled read-only (the hang is locked once others have replied)
export default class NpnHangEditor extends Component {
  @tracked selectedIds = [];
  @tracked dragging = null;

  willDestroy() {
    super.willDestroy(...arguments);
    window.removeEventListener("pointermove", this.onDrag);
    window.removeEventListener("pointerup", this.endResize);
    window.removeEventListener("pointercancel", this.endResize);
  }

  get images() {
    return (this.args.images ?? []).map((entry, index) => ({
      number: String(index + 1),
      upload_id: entry.upload.id,
      url: entry.upload.url,
      width: entry.upload.width,
      height: entry.upload.height,
    }));
  }

  get hang() {
    return resolveHang(this.args.hang, this.args.intent, this.images);
  }

  get selected() {
    const ids = new Set(this.selectedIds);
    return new Set(
      this.images
        .map((image, index) => (ids.has(image.upload_id) ? index : -1))
        .filter((index) => index >= 0)
    );
  }

  get selectedIndexes() {
    return [...this.selected].sort((a, b) => a - b);
  }

  get hangWidthLabel() {
    const wall = layoutWall(this.images.map(aspectOf), this.hang);
    return formatWallWidth(wall.hangWidth, this.hang.unit);
  }

  get selectionLabel() {
    const indexes = this.selectedIndexes;
    if (indexes.length === 1) {
      const image = this.images[indexes[0]];
      return i18n("npn_submissions.hang.selected_one", {
        number: image.number,
        size: formatPrintSize(
          this.hang.sizes[indexes[0]],
          aspectOf(image),
          this.hang.unit
        ),
      });
    }
    return i18n("npn_submissions.hang.selected_many", {
      count: indexes.length,
    });
  }

  get hasSelection() {
    return this.selectedIndexes.length > 0;
  }

  get canGrow() {
    return this.selectedIndexes.some(
      (i) => this.hang.sizes[i] < PRINT_SIZES.at(-1)
    );
  }

  get canShrink() {
    return this.selectedIndexes.some(
      (i) => this.hang.sizes[i] > PRINT_SIZES[0]
    );
  }

  _option(group, value, current, swatch = null) {
    return {
      group,
      value,
      active: current === value,
      label: i18n(`npn_submissions.hang.${group}_${value}`),
      swatch: swatch ? htmlSafe(`background-color:${swatch}`) : null,
    };
  }

  get controls() {
    const h = this.hang;
    const groups = [
      {
        key: "layout",
        options: LAYOUTS.map((v) => this._option("layout", v, h.layout)),
      },
      {
        key: "wall",
        options: Object.keys(WALLS).map((v) =>
          this._option("wall", v, h.wall, WALLS[v].color)
        ),
      },
      {
        key: "mat",
        options: Object.keys(MATS).map((v) =>
          this._option("mat", v, h.mat, MATS[v])
        ),
      },
    ];
    if (MATS[h.mat]) {
      groups.push({
        key: "mat_width",
        options: MAT_WIDTHS.map((v) => ({
          group: "mat_width",
          value: v,
          active: h.matWidth === v,
          label:
            h.unit === "cm"
              ? `${Math.round(v * 2.54)} cm`
              : i18n("npn_submissions.hang.inches", { count: v }),
        })),
      });
    }
    groups.push({
      key: "frame",
      options: Object.keys(FRAMES).map((v) =>
        this._option("frame", v, h.frame, FRAMES[v])
      ),
    });
    if (h.physical) {
      groups.push({
        key: "unit",
        options: ["in", "cm"].map((v) => this._option("unit", v, h.unit)),
      });
    }
    return groups.map((group) => ({
      ...group,
      heading: i18n(`npn_submissions.hang.${group.key}`),
    }));
  }

  get intentNote() {
    return this.hang.physical
      ? null
      : i18n("npn_submissions.hang.digital_note");
  }

  emit(next) {
    this.args.onChange?.(serializeHang(next, this.images));
  }

  @action
  setOption(group, value) {
    const next = { ...this.hang };
    if (group === "mat_width") {
      next.matWidth = value;
    } else if (group === "layout") {
      next.layout = value;
      // A lead print should lead: give it more presence when every print is
      // still the same size.
      const sizes = next.sizes;
      if (
        value === "lead" &&
        next.physical &&
        sizes.length > 2 &&
        sizes.every((s) => s === sizes[0])
      ) {
        next.sizes = [stepSize(stepSize(sizes[0], 1), 1), ...sizes.slice(1)];
      }
    } else {
      next[group] = value;
    }
    this.emit(next);
  }

  @action
  selectPrint(index, event) {
    if (this.args.disabled) {
      return;
    }
    const id = this.images[index]?.upload_id;
    if (!id) {
      return;
    }
    const multi = event?.shiftKey || event?.metaKey || event?.ctrlKey;
    if (multi) {
      this.selectedIds = this.selectedIds.includes(id)
        ? this.selectedIds.filter((x) => x !== id)
        : [...this.selectedIds, id];
    } else {
      this.selectedIds =
        this.selectedIds.length === 1 && this.selectedIds[0] === id ? [] : [id];
    }
  }

  @action
  selectAll() {
    this.selectedIds = this.images.map((image) => image.upload_id);
  }

  @action
  clearSelection() {
    this.selectedIds = [];
  }

  setSizes(indexes, sizeFor) {
    const next = { ...this.hang, sizes: [...this.hang.sizes] };
    indexes.forEach((i) => {
      next.sizes[i] = sizeFor(next.sizes[i], i);
    });
    this.emit(next);
  }

  @action
  grow() {
    this.setSizes(this.selectedIndexes, (size) => stepSize(size, 1));
  }

  @action
  shrink() {
    this.setSizes(this.selectedIndexes, (size) => stepSize(size, -1));
  }

  @action
  matchOthers() {
    const [first] = this.selectedIndexes;
    const size = this.hang.sizes[first];
    this.setSizes(
      this.images.map((_, i) => i),
      () => size
    );
  }

  @action
  resetHang() {
    this.selectedIds = [];
    this.args.onChange?.(null);
  }

  // --- drag to resize --------------------------------------------------------

  @action
  startResize(index, event) {
    if (this.args.disabled || index < 0) {
      return;
    }
    event.preventDefault();
    event.stopPropagation();
    const wallEl = event.target.closest(".npn-hang-wall");
    const frameEl = wallEl?.querySelectorAll(".npn-hang-wall__frame")[index];
    if (!frameEl) {
      return;
    }
    const rect = frameEl.getBoundingClientRect();
    const id = this.images[index].upload_id;
    // Dragging an unselected print resizes just that one; dragging a
    // selected print resizes the whole selection to the same size.
    if (!this.selectedIds.includes(id)) {
      this.selectedIds = [id];
    }
    this.dragging = {
      index,
      startX: event.clientX,
      startY: event.clientY,
      startSize: this.hang.sizes[index],
      startPx: Math.max(rect.width, rect.height),
      indexes: this.selectedIndexes,
    };
    window.addEventListener("pointermove", this.onDrag);
    window.addEventListener("pointerup", this.endResize, { once: true });
    window.addEventListener("pointercancel", this.endResize, { once: true });
  }

  @action
  onDrag(event) {
    const d = this.dragging;
    if (!d) {
      return;
    }
    // Growth along the diagonal, relative to the frame's size when the drag
    // started; snapped to the nearest standard print size.
    const delta = (event.clientX - d.startX + (event.clientY - d.startY)) / 2;
    const scale = Math.max(0.2, 1 + delta / d.startPx);
    const size = snapSize(d.startSize * scale);
    if (size !== this.hang.sizes[d.index]) {
      this.setSizes(d.indexes, () => size);
    }
  }

  @action
  endResize() {
    window.removeEventListener("pointermove", this.onDrag);
    this.dragging = null;
  }

  <template>
    <section
      class="npn-hang-editor
        {{if @disabled '--disabled'}}
        {{if this.dragging '--dragging'}}"
    >
      {{#if @disabled}}
        <p class="npn-help npn-hang-editor__locked">
          {{i18n "npn_submissions.hang.locked"}}
        </p>
      {{else}}
        <div class="npn-hang-editor__controls">
          {{#each this.controls as |group|}}
            <div
              class="npn-hang-editor__group"
              role="group"
              aria-label={{group.heading}}
            >
              <span class="npn-hang-editor__group-heading">
                {{group.heading}}
              </span>
              {{#each group.options as |option|}}
                <button
                  type="button"
                  class="npn-hang-editor__option
                    {{if option.active 'is-active'}}"
                  aria-pressed={{if option.active "true" "false"}}
                  {{on "click" (fn this.setOption option.group option.value)}}
                >
                  {{#if option.swatch}}
                    <span
                      class="npn-hang-editor__swatch"
                      style={{option.swatch}}
                    ></span>
                  {{/if}}
                  {{option.label}}
                </button>
              {{/each}}
            </div>
          {{/each}}
        </div>
      {{/if}}

      <div class="npn-hang-editor__canvas" {{gripListener this.startResize}}>
        <NpnHangWall
          @images={{this.images}}
          @hang={{this.hang}}
          @editable={{if @disabled false true}}
          @selected={{this.selected}}
          @onPrint={{this.selectPrint}}
        />
      </div>

      <div class="npn-hang-editor__status">
        {{#if this.hang.physical}}
          <span class="npn-hang-editor__width">
            {{i18n "npn_submissions.hang.hang_width" width=this.hangWidthLabel}}
          </span>
        {{else}}
          <span class="npn-hang-editor__width">{{this.intentNote}}</span>
        {{/if}}

        {{#unless @disabled}}
          {{#if this.hang.physical}}
            {{#if this.hasSelection}}
              <span class="npn-hang-editor__selection">
                {{this.selectionLabel}}
              </span>
              <DButton
                @action={{this.shrink}}
                @icon="minus"
                @title="npn_submissions.hang.smaller"
                @disabled={{if this.canShrink false true}}
                class="btn-default btn-small"
              />
              <DButton
                @action={{this.grow}}
                @icon="plus"
                @title="npn_submissions.hang.larger"
                @disabled={{if this.canGrow false true}}
                class="btn-default btn-small"
              />
              {{#if (eq this.selectedIndexes.length 1)}}
                <DButton
                  @action={{this.matchOthers}}
                  @label="npn_submissions.hang.match_others"
                  class="btn-flat btn-small"
                />
              {{/if}}
              <DButton
                @action={{this.clearSelection}}
                @label="npn_submissions.hang.done"
                class="btn-flat btn-small"
              />
            {{else}}
              <span class="npn-hang-editor__hint">
                {{i18n "npn_submissions.hang.hint"}}
              </span>
              <DButton
                @action={{this.selectAll}}
                @label="npn_submissions.hang.select_all"
                class="btn-flat btn-small"
              />
            {{/if}}
          {{/if}}
          <DButton
            @action={{this.resetHang}}
            @label="npn_submissions.hang.reset"
            class="btn-flat btn-small npn-hang-editor__reset"
          />
        {{/unless}}
      </div>
    </section>
  </template>
}

function eq(a, b) {
  return a === b;
}
