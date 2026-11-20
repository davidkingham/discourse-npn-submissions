import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { trustHTML } from "@ember/template";
import { modifier } from "ember-modifier";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import { formatShorthand, parseShorthand } from "../lib/npn-sequence";
import {
  aspectOf,
  BOOK_FORMATS,
  defaultOrderName,
  formatPrintSize,
  formatWallWidth,
  FRAMES,
  FREE_LAYOUT,
  FREE_MIN_CLEARANCE,
  LAYOUTS,
  layoutWall,
  MAT_WIDTHS,
  MATS,
  MAX_EXTRA_ORDERS,
  ordersAllowed,
  positionsFromLayout,
  PRINT_SIZES,
  resolveHang,
  resolveOrders,
  serializeHang,
  serializeOrders,
  snapPosition,
  snapSize,
  stepSize,
  WALLS,
} from "../lib/npn-wall-layout";
import NpnHangWall from "./npn-hang-wall";

// Grips are bound with a plain listener (pointerdown is the right event for
// starting a drag; the template lint rule is about click-like handlers).
const gripListener = modifier((element, [onGrip, onPrint, onKey]) => {
  const handler = (event) => {
    const grip = event.target.closest?.(".npn-hang-wall__grip");
    if (grip) {
      const grips = [...element.querySelectorAll(".npn-hang-wall__grip")];
      onGrip(grips.indexOf(grip), event);
      return;
    }
    // Salon hang: pressing on a print starts moving it.
    const print = event.target.closest?.(".npn-hang-wall__print");
    if (print) {
      const prints = [...element.querySelectorAll(".npn-hang-wall__print")];
      onPrint?.(prints.indexOf(print), event);
    }
  };
  const keyHandler = (event) => onKey?.(event);
  element.addEventListener("pointerdown", handler);
  element.addEventListener("keydown", keyHandler);
  return () => {
    element.removeEventListener("pointerdown", handler);
    element.removeEventListener("keydown", keyHandler);
  };
});

const DRAG_THRESHOLD = 4; // px before a press on a print becomes a move

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
  @tracked dragging = null;
  // Which order is on the wall: 0 = the main order, 1+ = a proposed order.
  @tracked activeOrder = 0;
  @tracked orderDraft = null;
  @tracked orderProblem = null;
  // Salon hang: the drag in progress and the lines it snapped to.
  @tracked guides = null;
  moving = null;
  suppressClick = false;
  @tracked _selectedIds = [];

  willDestroy() {
    super.willDestroy(...arguments);
    window.removeEventListener("pointermove", this.onDrag);
    window.removeEventListener("pointermove", this.onMove);
    window.removeEventListener("pointerup", this.endMove);
    window.removeEventListener("pointercancel", this.endMove);
    window.removeEventListener("pointerup", this.endResize);
    window.removeEventListener("pointercancel", this.endResize);
  }

  // With @selectedNumbers the parent owns the selection (a critic's tool,
  // which also changes it when prints are left out or put back); otherwise
  // the editor keeps it.
  get selectedIds() {
    const numbers = this.args.selectedNumbers;
    if (numbers) {
      return this.images
        .filter((image) => numbers.includes(image.number))
        .map((image) => image.upload_id);
    }
    return this._selectedIds;
  }

  set selectedIds(ids) {
    this._selectedIds = ids;
    this.notifySelection();
  }

  // @prints: already-numbered prints (a critic's suggestion: original
  // numbers, alternates as A1…). Otherwise @images are form entries,
  // numbered by position.
  get allImages() {
    if (this.args.prints) {
      return this.args.prints;
    }
    return (this.args.images ?? []).map((entry, index) => ({
      number: String(index + 1),
      upload_id: entry.upload.id,
      url: entry.upload.url,
      width: entry.upload.width,
      height: entry.upload.height,
    }));
  }

  // The prints as shown on the wall: in the main order, or rearranged into
  // the proposed order being edited. Numbers stay the main order's.
  get images() {
    const all = this.allImages;
    const order = this.orders[this.activeOrderIndex];
    return order && this.activeOrderIndex > 0
      ? order.indexes.map((i) => all[i])
      : all;
  }

  // --- proposed orders (@allowOrders) ---------------------------------------

  get ordersEnabled() {
    return (
      !!this.args.allowOrders &&
      ordersAllowed(this.args.intent) &&
      this.args.hang?.layout !== FREE_LAYOUT
    );
  }

  get orders() {
    return this.ordersEnabled
      ? resolveOrders(this.args.hang, this.args.intent, this.allImages)
      : [];
  }

  get activeOrderIndex() {
    return Math.min(this.activeOrder, Math.max(this.orders.length - 1, 0));
  }

  get editingExtraOrder() {
    return this.ordersEnabled && this.activeOrderIndex > 0;
  }

  get orderTabs() {
    return this.orders.map((order, index) => ({
      index,
      name: order.name,
      active: index === this.activeOrderIndex,
    }));
  }

  get canAddOrder() {
    return (
      this.ordersEnabled &&
      !this.args.disabled &&
      this.allImages.length > 1 &&
      this.orders.length <= MAX_EXTRA_ORDERS
    );
  }

  get activeOrderName() {
    return this.orders[this.activeOrderIndex]?.name ?? "";
  }

  get activeOrderShorthand() {
    return this.orderDraft ?? formatShorthand(this.images.map((i) => i.number));
  }

  get canMoveInOrder() {
    return this.editingExtraOrder && this.selectedIndexes.length === 1;
  }

  emitOrders(orders) {
    const base =
      this.args.hang ?? serializeHang(this.hang, this.images, this.args.hang);
    this.args.onChange?.({
      ...base,
      ...serializeOrders(orders, this.allImages),
    });
  }

  updateActiveOrder(change) {
    const orders = this.orders.map((o) => ({ ...o, indexes: [...o.indexes] }));
    change(orders[this.activeOrderIndex], orders);
    this.emitOrders(orders);
  }

  @action
  selectOrder(index) {
    this.activeOrder = index;
    this.orderDraft = null;
    this.orderProblem = null;
    this.selectedIds = [];
  }

  // A new proposal starts as the order on screen, ready to rearrange.
  @action
  addOrder() {
    const orders = this.orders.map((o) => ({ ...o }));
    const current = orders[this.activeOrderIndex];
    orders.push({
      name: defaultOrderName(orders.length),
      indexes: [...current.indexes],
    });
    this.emitOrders(orders);
    this.selectOrder(orders.length - 1);
  }

  @action
  removeOrder() {
    const orders = this.orders.filter((_, i) => i !== this.activeOrderIndex);
    this.emitOrders(orders);
    this.selectOrder(0);
  }

  @action
  renameOrder(event) {
    const name = event.target.value.slice(0, 40);
    this.updateActiveOrder((order) => (order.name = name));
  }

  // "9, 8, 7 …" typed for the proposed order: applied once it names every
  // print exactly once.
  @action
  typeOrder(event) {
    this.orderDraft = event.target.value;
    const all = this.allImages;
    const known = new Set(all.map((image) => image.number));
    const { numbers, invalid, unknown } = parseShorthand(
      this.orderDraft,
      known
    );
    if (invalid.length || unknown.length || numbers.length !== all.length) {
      this.orderProblem = i18n("npn_submissions.orders.incomplete", {
        count: all.length,
      });
      return;
    }
    this.orderProblem = null;
    const indexOf = new Map(all.map((image, i) => [image.number, i]));
    this.updateActiveOrder(
      (order) => (order.indexes = numbers.map((n) => indexOf.get(n)))
    );
  }

  @action
  typeOrderDone() {
    if (!this.orderProblem) {
      this.orderDraft = null;
    }
  }

  @action
  moveInOrder(direction) {
    const from = this.selectedIndexes[0];
    const to = from + direction;
    if (to < 0 || to >= this.images.length) {
      return;
    }
    this.orderDraft = null;
    this.updateActiveOrder((order) => {
      const [moved] = order.indexes.splice(from, 1);
      order.indexes.splice(to, 0, moved);
    });
  }

  get hang() {
    return resolveHang(this.args.hang, this.args.intent, this.images, [
      ...this.images,
      ...this.coverAlternates,
    ]);
  }

  // --- salon: move prints by hand ----------------------------------------

  get isFree() {
    return this.hang.layout === FREE_LAYOUT && this.hang.physical;
  }

  // Every print's frame as { cx, cy, w, h } (cy = height above the floor).
  frames() {
    const wall = layoutWall(this.images.map(aspectOf), this.hang);
    const centres = positionsFromLayout(wall);
    const byIndex = [...wall.boxes].sort((a, b) => a.index - b.index);
    return byIndex.map((b, i) => ({
      cx: centres[i][0],
      cy: centres[i][1],
      w: b.w,
      h: b.h,
    }));
  }

  // Moves the prints at `indexes` so that the lead one (`index`) sits at
  // (cx, cy), keeping the others' offsets from it, and inside the wall.
  placePrints(frames, index, indexes, cx, cy) {
    const dx = cx - frames[index].cx;
    const dy = cy - frames[index].cy;
    const positions = frames.map((f) => [f.cx, f.cy]);
    indexes.forEach((i) => {
      const f = frames[i];
      positions[i] = [
        Math.max(f.w / 2 + 2, f.cx + dx),
        Math.max(f.h / 2 + FREE_MIN_CLEARANCE, f.cy + dy),
      ];
    });
    this.emit({ ...this.hang, positions });
  }

  @action
  startMove(index, event) {
    if (this.args.disabled || !this.isFree || index < 0 || event.button > 0) {
      return;
    }
    const wallEl = event.target.closest(".npn-hang-wall");
    const wall = layoutWall(this.images.map(aspectOf), this.hang);
    const id = this.images[index].upload_id;
    this.moving = {
      index,
      startX: event.clientX,
      startY: event.clientY,
      inchesPerPx: wall.width / wallEl.clientWidth,
      frames: this.frames(),
      // Dragging a selected print moves the whole selection.
      indexes: this.selectedIds.includes(id) ? this.selectedIndexes : [index],
      moved: false,
    };
    window.addEventListener("pointermove", this.onMove);
    window.addEventListener("pointerup", this.endMove, { once: true });
    window.addEventListener("pointercancel", this.endMove, { once: true });
  }

  @action
  onMove(event) {
    const m = this.moving;
    if (!m) {
      return;
    }
    const dxPx = event.clientX - m.startX;
    const dyPx = event.clientY - m.startY;
    if (!m.moved && Math.hypot(dxPx, dyPx) < DRAG_THRESHOLD) {
      return;
    }
    m.moved = true;
    const frame = m.frames[m.index];
    const others = m.frames.filter((_, i) => !m.indexes.includes(i));
    const snapped = snapPosition(
      frame.cx + dxPx * m.inchesPerPx,
      frame.cy - dyPx * m.inchesPerPx,
      frame.w,
      frame.h,
      others
    );
    this.guides = { x: snapped.guideX, y: snapped.guideY };
    this.placePrints(m.frames, m.index, m.indexes, snapped.cx, snapped.cy);
  }

  @action
  endMove() {
    window.removeEventListener("pointermove", this.onMove);
    if (this.moving?.moved) {
      this.suppressClick = true;
      // If the press ended off the print no click follows; don't swallow
      // the next real one.
      setTimeout(() => (this.suppressClick = false), 0);
    }
    this.moving = null;
    this.guides = null;
  }

  // Arrow keys nudge the selected prints an inch (five with Shift).
  @action
  nudge(event) {
    const arrows = {
      ArrowLeft: [-1, 0],
      ArrowRight: [1, 0],
      ArrowUp: [0, 1],
      ArrowDown: [0, -1],
    };
    const step = arrows[event.key];
    const indexes = this.selectedIndexes;
    if (!step || !this.isFree || this.args.disabled || !indexes.length) {
      return;
    }
    event.preventDefault();
    const by = event.shiftKey ? 5 : 1;
    const frames = this.frames();
    const lead = indexes[0];
    this.placePrints(
      frames,
      lead,
      indexes,
      frames[lead].cx + step[0] * by,
      frames[lead].cy + step[1] * by
    );
  }

  // --- book spreads ------------------------------------------------------

  get isBook() {
    return this.hang.mode === "spreads";
  }

  // Alternates a book's cover may also be chosen from (@alternates: numbered
  // prints, "A1"…).
  get coverAlternates() {
    return this.args.alternates ?? [];
  }

  // The one selected print's spread: { position, spread } or null.
  get selectedSpread() {
    const indexes = this.selectedIndexes;
    if (!this.isBook || indexes.length !== 1) {
      return null;
    }
    const position = this.hang.spreads.findIndex((s) =>
      s.indexes.includes(indexes[0])
    );
    return position < 0
      ? null
      : { position, spread: this.hang.spreads[position], index: indexes[0] };
  }

  get bookTools() {
    const selected = this.selectedSpread;
    if (!selected) {
      return null;
    }
    const { position, spread, index } = selected;
    const next = this.hang.spreads[position + 1];
    const single = spread.indexes.length === 1;
    const coverId = this.hang.coverImage?.upload_id;
    return {
      label: i18n("npn_submissions.book.selected", {
        number: this.images[index].number,
      }),
      sides: single
        ? ["left", "right", "full"].map((side) => ({
            side,
            label: i18n(`npn_submissions.book.side_${side}`),
            active: spread.side === side,
          }))
        : [],
      canPair: single && next?.indexes.length === 1,
      canSplit: !single,
      isCover: coverId === this.images[index].upload_id,
    };
  }

  get coverOptions() {
    const coverId = this.hang.coverImage?.upload_id;
    return this.coverAlternates.map((image) => ({
      image,
      label: image.number,
      active: coverId === image.upload_id,
    }));
  }

  updateSpreads(change) {
    const spreads = this.hang.spreads.map((s) => ({
      ...s,
      indexes: [...s.indexes],
    }));
    change(spreads);
    this.emit({ ...this.hang, spreads });
  }

  @action
  setSide(side) {
    const selected = this.selectedSpread;
    if (selected) {
      this.updateSpreads((spreads) => (spreads[selected.position].side = side));
    }
  }

  @action
  pairWithNext() {
    const selected = this.selectedSpread;
    if (!selected) {
      return;
    }
    this.updateSpreads((spreads) => {
      const [next] = spreads.splice(selected.position + 1, 1);
      spreads[selected.position] = {
        indexes: [...spreads[selected.position].indexes, ...next.indexes],
        side: null,
      };
    });
  }

  @action
  splitSpread() {
    const selected = this.selectedSpread;
    if (!selected) {
      return;
    }
    this.updateSpreads((spreads) => {
      const [a, b] = spreads[selected.position].indexes;
      spreads.splice(
        selected.position,
        1,
        { indexes: [a], side: "right" },
        { indexes: [b], side: "right" }
      );
    });
  }

  // Use the selected image (or an alternate) as the cover; again to clear.
  @action
  toggleCover(image) {
    const target = image ?? this.images[this.selectedIndexes[0]];
    if (!target) {
      return;
    }
    const current = this.hang.coverImage?.upload_id;
    this.emit({
      ...this.hang,
      coverImage: current === target.upload_id ? null : target,
    });
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
      swatch: swatch ? trustHTML(`background-color:${swatch}`) : null,
    };
  }

  get controls() {
    const h = this.hang;
    const groups = [
      {
        key: "layout",
        // A salon hang needs real sizes and a floor: a physical show only.
        options: LAYOUTS.filter((v) => v !== FREE_LAYOUT || h.physical).map(
          (v) => this._option("layout", v, h.layout)
        ),
      },
      {
        key: "wall",
        options: Object.keys(WALLS).map((v) =>
          this._option("wall", v, h.wall, WALLS[v].color)
        ),
      },
    ];
    // A magazine or selection has no look to choose.
    if (h.mode === "sequence" || h.mode === "selection") {
      return [];
    }
    // A book: its page shape and the background it's shown on.
    if (h.mode === "spreads") {
      return [
        {
          key: "book_format",
          heading: i18n("npn_submissions.book.format"),
          options: Object.keys(BOOK_FORMATS).map((v) => ({
            group: "book_format",
            value: v,
            active: h.bookFormat === v,
            label: i18n(`npn_submissions.book.format_${v}`),
          })),
        },
        {
          key: "wall",
          heading: i18n("npn_submissions.book.background"),
          options: groups[1].options,
        },
      ];
    }
    // A web page has a layout and a background, nothing more.
    if (h.mode !== "hang") {
      return groups.map((group) => ({
        ...group,
        heading: i18n(
          `npn_submissions.hang.${group.key === "wall" ? "page" : "page_layout"}`
        ),
      }));
    }
    groups.push({
      key: "mat",
      options: Object.keys(MATS).map((v) =>
        this._option("mat", v, h.mat, MATS[v])
      ),
    });
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
    return this.hang.mode === "page"
      ? i18n("npn_submissions.hang.page_note")
      : null;
  }

  emit(next) {
    this.args.onChange?.(serializeHang(next, this.images, this.args.hang));
  }

  @action
  setOption(group, value) {
    const next = { ...this.hang };
    if (group === "book_format") {
      next.bookFormat = value;
    } else if (group === "mat_width") {
      next.matWidth = value;
    } else if (group === "layout") {
      // A salon hang starts from where the prints are now.
      if (value === FREE_LAYOUT && next.layout !== FREE_LAYOUT) {
        next.positions = positionsFromLayout(
          layoutWall(this.images.map(aspectOf), this.hang)
        );
      }
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
    // The click that ends a drag isn't a selection.
    if (this.suppressClick) {
      this.suppressClick = false;
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

  // Lets a parent act on the selection (a critic ranking prints).
  notifySelection() {
    const ids = this._selectedIds;
    this.args.onSelectionChange?.(
      this.images
        .filter((image) => ids.includes(image.upload_id))
        .map((image) => image.number)
    );
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

      {{#if this.ordersEnabled}}
        <div class="npn-hang-editor__orders">
          <span class="npn-hang-editor__group-heading">
            {{i18n "npn_submissions.orders.label"}}
          </span>
          {{#each this.orderTabs as |tab|}}
            <button
              type="button"
              class="npn-hang-editor__option {{if tab.active 'is-active'}}"
              aria-pressed={{if tab.active "true" "false"}}
              {{on "click" (fn this.selectOrder tab.index)}}
            >{{tab.name}}</button>
          {{/each}}
          {{#if this.canAddOrder}}
            <DButton
              @action={{this.addOrder}}
              @icon="plus"
              @label="npn_submissions.orders.add"
              class="btn-flat btn-small"
            />
          {{/if}}
        </div>
        {{#if this.editingExtraOrder}}
          {{#unless @disabled}}
            <div class="npn-hang-editor__order-edit">
              <label>
                <span>{{i18n "npn_submissions.orders.name"}}</span>
                <input
                  type="text"
                  value={{this.activeOrderName}}
                  maxlength="40"
                  {{on "change" this.renameOrder}}
                />
              </label>
              <label class="--order">
                <span>{{i18n "npn_submissions.orders.order"}}</span>
                <input
                  type="text"
                  value={{this.activeOrderShorthand}}
                  {{on "input" this.typeOrder}}
                  {{on "blur" this.typeOrderDone}}
                />
              </label>
              <DButton
                @action={{this.removeOrder}}
                @icon="trash-can"
                @label="npn_submissions.orders.remove"
                class="btn-flat btn-small"
              />
            </div>
            {{#if this.orderProblem}}
              <p class="npn-field__error">{{this.orderProblem}}</p>
            {{/if}}
          {{/unless}}
        {{else if this.canAddOrder}}
          <p class="npn-help npn-hang-editor__orders-help">
            {{i18n "npn_submissions.orders.help"}}
          </p>
        {{/if}}
      {{/if}}

      <div
        class="npn-hang-editor__canvas {{if this.isFree '--free'}}"
        {{gripListener this.startResize this.startMove this.nudge}}
      >
        <NpnHangWall
          @images={{this.images}}
          @hang={{this.hang}}
          @guides={{this.guides}}
          @editable={{if @disabled false true}}
          @selected={{this.selected}}
          @marks={{@marks}}
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
          {{#if this.canMoveInOrder}}
            <DButton
              @action={{fn this.moveInOrder -1}}
              @icon="arrow-left"
              @title="npn_submissions.orders.earlier"
              class="btn-default btn-small"
            />
            <DButton
              @action={{fn this.moveInOrder 1}}
              @icon="arrow-right"
              @title="npn_submissions.orders.later"
              class="btn-default btn-small"
            />
          {{/if}}
          {{#if this.isBook}}
            {{#if this.bookTools}}
              <span class="npn-hang-editor__selection">
                {{this.bookTools.label}}
              </span>
              {{#each this.bookTools.sides as |option|}}
                <button
                  type="button"
                  class="npn-hang-editor__option
                    {{if option.active 'is-active'}}"
                  aria-pressed={{if option.active "true" "false"}}
                  {{on "click" (fn this.setSide option.side)}}
                >{{option.label}}</button>
              {{/each}}
              {{#if this.bookTools.canPair}}
                <DButton
                  @action={{this.pairWithNext}}
                  @label="npn_submissions.book.pair"
                  class="btn-default btn-small"
                />
              {{/if}}
              {{#if this.bookTools.canSplit}}
                <DButton
                  @action={{this.splitSpread}}
                  @label="npn_submissions.book.split"
                  class="btn-default btn-small"
                />
              {{/if}}
              <DButton
                @action={{fn this.toggleCover null}}
                @label={{if
                  this.bookTools.isCover
                  "npn_submissions.book.cover_remove"
                  "npn_submissions.book.cover_use"
                }}
                class="btn-default btn-small"
              />
            {{else}}
              <span class="npn-hang-editor__hint">
                {{i18n "npn_submissions.book.hint"}}
              </span>
            {{/if}}
            {{#if this.coverOptions.length}}
              <span class="npn-hang-editor__cover-alternates">
                {{i18n "npn_submissions.book.cover_from_alternates"}}
                {{#each this.coverOptions as |option|}}
                  <button
                    type="button"
                    class="npn-hang-editor__option
                      {{if option.active 'is-active'}}"
                    aria-pressed={{if option.active "true" "false"}}
                    {{on "click" (fn this.toggleCover option.image)}}
                  >{{option.label}}</button>
                {{/each}}
              </span>
            {{/if}}
          {{/if}}
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
                {{#if this.isFree}}
                  {{i18n "npn_submissions.hang.salon_hint"}}
                {{else}}
                  {{i18n "npn_submissions.hang.hint"}}
                {{/if}}
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
