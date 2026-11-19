import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { htmlSafe } from "@ember/template";
import { modifier } from "ember-modifier";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import { openProjectViewer } from "../lib/npn-project-viewer";
import {
  aspectOf,
  framedSize,
  FRAMES,
  MATS,
  WALLS,
} from "../lib/npn-wall-layout";

// Gap between frames on the walk, in inches.
const WALK_GAP = 8;
const SWIPE_MIN = 40;

const didInsertWalk = modifier((element, [callback]) => {
  callback(element);
});

function n(value) {
  return Math.round(value * 1000) / 1000;
}

// "Walk the wall": the project full-screen, hung in one line on the chosen
// wall. The current print sits in the middle, large; its neighbours peek in
// at the edges. Arrow keys, swipe, or tapping a neighbour moves along; a
// strip at the bottom shows the whole wall and where you are. Escape closes.
//
// Sizes are pure CSS: --u is one wall unit, chosen so the tallest framed
// print fits 64% of the screen height and the widest 62% of its width, so
// the neighbours always peek in at the sides.
export default class NpnWallWalk extends Component {
  @tracked index = this.args.start ?? 0;

  pointerStart = null;
  previousFocus = null;

  willDestroy() {
    super.willDestroy(...arguments);
    document.removeEventListener("keydown", this.onKeydown);
    document.body.classList.remove("npn-wall-walk-open");
    this.previousFocus?.focus?.();
  }

  get images() {
    return this.args.images ?? [];
  }

  get style() {
    return this.args.hang;
  }

  get sizes() {
    return this.images.map((image, index) =>
      framedSize(aspectOf(image), this.style.sizes?.[index] ?? 20, this.style)
    );
  }

  get rootStyle() {
    const maxH = Math.max(...this.sizes.map((s) => s.h));
    const maxW = Math.max(...this.sizes.map((s) => s.w));
    const wall = WALLS[this.style.wall];
    return htmlSafe(
      `--u:min(calc(64vh / ${n(maxH)}), calc(62vw / ${n(maxW)}));` +
        `--wall:${wall.color};`
    );
  }

  get wallClass() {
    return WALLS[this.style.wall].dark ? "--dark-wall" : "--light-wall";
  }

  get prints() {
    const mat = MATS[this.style.mat];
    const frame = FRAMES[this.style.frame];
    const total = this.images.length;
    return this.images.map((image, index) => {
      const size = this.sizes[index];
      const inset = size.mat + size.frame;
      const label = i18n("npn_submissions.exhibition.image_label", {
        number: image.number,
        total,
      });
      return {
        index,
        image,
        label,
        current: index === this.index,
        src: image.sheet_url || image.url,
        style: htmlSafe(
          `width:calc(var(--u) * ${n(size.w)});height:calc(var(--u) * ${n(size.h)});` +
            `background-color:${frame || mat || "transparent"};`
        ),
        matStyle: mat
          ? htmlSafe(
              `inset:calc(var(--u) * ${n(size.frame)});background-color:${mat};`
            )
          : null,
        printStyle: htmlSafe(
          `top:calc(var(--u) * ${n(inset)});left:calc(var(--u) * ${n(inset)});` +
            `width:calc(var(--u) * ${n(size.printW)});height:calc(var(--u) * ${n(size.printH)});`
        ),
        framed: !!frame,
      };
    });
  }

  // Slide the track so the current print's centre sits mid-screen.
  get trackStyle() {
    let offset = 0;
    for (let i = 0; i < this.index; i++) {
      offset += this.sizes[i].w + WALK_GAP;
    }
    offset += this.sizes[this.index].w / 2;
    return htmlSafe(
      `gap:calc(var(--u) * ${WALK_GAP});transform:translateX(calc(50vw - var(--u) * ${n(offset)}));`
    );
  }

  get current() {
    return this.images[this.index];
  }

  get caption() {
    const image = this.current;
    const label = i18n("npn_submissions.exhibition.image_label", {
      number: image.number,
      total: this.images.length,
    });
    return image.caption ? `${label}: ${image.caption}` : label;
  }

  get atStart() {
    return this.index === 0;
  }

  get atEnd() {
    return this.index === this.images.length - 1;
  }

  @action
  setup(element) {
    this.previousFocus = document.activeElement;
    document.body.classList.add("npn-wall-walk-open");
    document.addEventListener("keydown", this.onKeydown);
    element.focus();
  }

  @action
  onKeydown(event) {
    if (event.key === "Escape") {
      event.preventDefault();
      this.args.onClose?.();
    } else if (event.key === "ArrowRight") {
      event.preventDefault();
      this.next();
    } else if (event.key === "ArrowLeft") {
      event.preventDefault();
      this.previous();
    } else if (event.key === "Home") {
      this.goTo(0);
    } else if (event.key === "End") {
      this.goTo(this.images.length - 1);
    }
  }

  @action
  next() {
    this.goTo(this.index + 1);
  }

  @action
  previous() {
    this.goTo(this.index - 1);
  }

  @action
  goTo(index) {
    this.index = Math.max(0, Math.min(this.images.length - 1, index));
  }

  @action
  clickPrint(index) {
    if (index === this.index) {
      openProjectViewer(this.images, index);
    } else {
      this.goTo(index);
    }
  }

  @action
  viewLarge() {
    openProjectViewer(this.images, this.index);
  }

  @action
  touchStart(event) {
    const touch = event.changedTouches?.[0];
    this.pointerStart = touch ? { x: touch.clientX, y: touch.clientY } : null;
  }

  @action
  touchEnd(event) {
    const start = this.pointerStart;
    const touch = event.changedTouches?.[0];
    this.pointerStart = null;
    if (!start || !touch) {
      return;
    }
    const dx = touch.clientX - start.x;
    if (
      Math.abs(dx) > SWIPE_MIN &&
      Math.abs(dx) > Math.abs(touch.clientY - start.y)
    ) {
      dx < 0 ? this.next() : this.previous();
    }
  }

  <template>
    <div
      class="npn-wall-walk {{this.wallClass}}"
      style={{this.rootStyle}}
      role="dialog"
      aria-modal="true"
      aria-label={{i18n "npn_submissions.exhibition.walk"}}
      tabindex="-1"
      {{didInsertWalk this.setup}}
    >
      <div class="npn-wall-walk__top">
        <span class="npn-wall-walk__caption" aria-live="polite">
          {{this.caption}}
        </span>
        <DButton
          @action={{this.viewLarge}}
          @icon="expand"
          @label="npn_submissions.exhibition.view_large"
          class="btn-flat npn-wall-walk__button"
        />
        <DButton
          @action={{@onClose}}
          @icon="xmark"
          @title="npn_submissions.exhibition.close"
          class="btn-flat npn-wall-walk__button npn-wall-walk__close"
        />
      </div>

      <div
        class="npn-wall-walk__stage"
        {{on "touchstart" this.touchStart passive=true}}
        {{on "touchend" this.touchEnd}}
      >
        <div class="npn-wall-walk__track" style={{this.trackStyle}}>
          {{#each this.prints as |print|}}
            <button
              type="button"
              class="npn-wall-walk__frame
                {{if print.framed '--framed'}}
                {{if print.current 'is-current'}}"
              style={{print.style}}
              aria-label={{print.label}}
              aria-current={{if print.current "true"}}
              tabindex={{if print.current "0" "-1"}}
              {{on "click" (fn this.clickPrint print.index)}}
            >
              {{#if print.matStyle}}
                <span
                  class="npn-wall-walk__mat"
                  style={{print.matStyle}}
                ></span>
              {{/if}}
              <img
                class="npn-wall-walk__print"
                style={{print.printStyle}}
                src={{print.src}}
                alt={{print.label}}
                draggable="false"
              />
            </button>
          {{/each}}
        </div>

        <DButton
          @action={{this.previous}}
          @icon="arrow-left"
          @title="npn_submissions.exhibition.previous"
          @disabled={{this.atStart}}
          class="btn-flat npn-wall-walk__nav --previous"
        />
        <DButton
          @action={{this.next}}
          @icon="arrow-right"
          @title="npn_submissions.exhibition.next"
          @disabled={{this.atEnd}}
          class="btn-flat npn-wall-walk__nav --next"
        />
      </div>

      <div
        class="npn-wall-walk__strip"
        role="group"
        aria-label={{i18n "npn_submissions.exhibition.strip"}}
      >
        {{#each this.prints as |print|}}
          <button
            type="button"
            class="npn-wall-walk__thumb {{if print.current 'is-current'}}"
            aria-label={{print.label}}
            aria-current={{if print.current "true"}}
            {{on "click" (fn this.goTo print.index)}}
          >
            <img src={{print.src}} alt="" draggable="false" />
          </button>
        {{/each}}
      </div>
    </div>
  </template>
}
