import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { trustHTML } from "@ember/template";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import { openProjectViewer } from "../lib/npn-project-viewer";
import {
  aspectOf,
  FRAMES,
  layoutWall,
  MATS,
  normalizeStyle,
  percentRect,
  WALLS,
} from "../lib/npn-wall-layout";
import NpnWallWalk from "./npn-wall-walk";

const STORAGE_KEY = "npn-exhibition-look";

function loadLook() {
  try {
    return JSON.parse(window.localStorage.getItem(STORAGE_KEY)) || null;
  } catch {
    return null;
  }
}

function saveLook(look) {
  try {
    if (look) {
      window.localStorage.setItem(STORAGE_KEY, JSON.stringify(look));
    } else {
      window.localStorage.removeItem(STORAGE_KEY);
    }
  } catch {
    // Private mode / blocked storage: the look just isn't remembered.
  }
}

function narrowScreen() {
  return window.matchMedia?.("(max-width: 600px)")?.matches ?? false;
}

function pct(value) {
  return `${Math.round(value * 1000) / 1000}%`;
}

function rectStyle(rect, wall) {
  const p = percentRect(rect, wall);
  return `left:${pct(p.left)};top:${pct(p.top)};width:${pct(p.width)};height:${pct(p.height)};`;
}

// Hangs a project on a wall at the top of the original post: every print at
// true relative proportions (same long edge), framed and matted, with its
// number on a small placard. Tap a print to see it large; "Walk the wall"
// opens a full-screen walk along it. Alternates hang on a separate short
// panel. "Try a look" lets a reader change wall / mat / frame / layout for
// themselves (remembered in their browser; the post never changes).
//
// @data: { images } — the topic's npn_project_images.
export default class NpnExhibitionWall extends Component {
  @tracked look = loadLook();
  @tracked lookOpen = false;
  @tracked walkStart = null;

  get images() {
    return this.args.data?.images ?? {};
  }

  get originals() {
    return this.images.originals ?? [];
  }

  get alternates() {
    return this.images.alternates ?? [];
  }

  get style() {
    const style = normalizeStyle(
      this.look,
      this.images.intent,
      this.originals.length
    );
    // On a phone, a line (or a lead print beside a grid) of more than three
    // prints is too small to read: hang rows of three instead.
    if (narrowScreen() && this.originals.length > 3) {
      return { ...style, layout: "rows", perRow: 3 };
    }
    return style;
  }

  get wallColor() {
    return WALLS[this.style.wall];
  }

  get wallClass() {
    return this.wallColor.dark ? "--dark-wall" : "--light-wall";
  }

  _hang(images, style, widthPercent = 100) {
    const wall = layoutWall(images.map(aspectOf), style);
    const mat = MATS[style.mat];
    const frame = FRAMES[style.frame];
    const total = this.originals.length;
    return {
      units: wall.width,
      style: trustHTML(
        `aspect-ratio:${wall.width} / ${wall.height};background-color:${this.wallColor.color};` +
          `width:${pct(widthPercent)};`
      ),
      prints: wall.boxes.map((b) => {
        const image = images[b.index];
        const isAlternate = image.number.startsWith("A");
        const label = isAlternate
          ? i18n("npn_submissions.exhibition.alternate_label", {
              number: image.number.slice(1),
            })
          : i18n("npn_submissions.exhibition.image_label", {
              number: image.number,
              total,
            });
        return {
          index: b.index,
          image,
          label,
          title: image.caption ? `${label}: ${image.caption}` : label,
          src: image.sheet_url || image.url,
          number: image.number,
          frameStyle: trustHTML(
            rectStyle(b, wall) +
              `background-color:${frame || mat || "transparent"};`
          ),
          matStyle: trustHTML(
            rectStyle(
              {
                x: b.x + b.frame,
                y: b.y + b.frame,
                w: b.w - b.frame * 2,
                h: b.h - b.frame * 2,
              },
              wall
            ) + `background-color:${mat || "transparent"};`
          ),
          printStyle: trustHTML(rectStyle(b.print, wall)),
          placardStyle: trustHTML(
            rectStyle({ x: b.x, y: b.placardY, w: b.w, h: 16 }, wall)
          ),
          framed: !!frame,
          matted: !!mat,
        };
      }),
    };
  }

  get mainWall() {
    return this._hang(this.originals, this.style);
  }

  get alternateWall() {
    if (!this.alternates.length) {
      return null;
    }
    // Same print size as the main wall, so alternates compare honestly.
    const style = { ...this.style, layout: "line" };
    const units = layoutWall(this.alternates.map(aspectOf), style).width;
    return this._hang(
      this.alternates,
      style,
      Math.min(100, (units / this.mainWall.units) * 100)
    );
  }

  get lookGroups() {
    const current = this.style;
    const option = (group, value) => ({
      group,
      value,
      label: i18n(`npn_submissions.exhibition.look.${group}_${value}`),
      active: current[group] === value,
      swatch:
        group === "wall"
          ? trustHTML(`background-color:${WALLS[value].color}`)
          : group === "mat" && MATS[value]
            ? trustHTML(`background-color:${MATS[value]}`)
            : group === "frame" && FRAMES[value]
              ? trustHTML(`background-color:${FRAMES[value]}`)
              : null,
    });
    return [
      {
        key: "wall",
        options: Object.keys(WALLS).map((v) => option("wall", v)),
      },
      { key: "mat", options: Object.keys(MATS).map((v) => option("mat", v)) },
      {
        key: "frame",
        options: Object.keys(FRAMES).map((v) => option("frame", v)),
      },
      {
        key: "layout",
        options: ["line", "rows", "lead"].map((v) => option("layout", v)),
      },
    ].map((group) => ({
      ...group,
      heading: i18n(`npn_submissions.exhibition.look.${group.key}`),
    }));
  }

  get hasCustomLook() {
    return !!this.look;
  }

  get revisionNote() {
    const revision = this.images.revision;
    return revision
      ? i18n("npn_submissions.exhibition.revision_note", { revision })
      : null;
  }

  @action
  openPrint(index) {
    openProjectViewer(this.originals, index);
  }

  @action
  openAlternate(index) {
    openProjectViewer(this.alternates, index);
  }

  @action
  startWalk() {
    this.walkStart = 0;
  }

  @action
  endWalk() {
    this.walkStart = null;
  }

  @action
  toggleLook() {
    this.lookOpen = !this.lookOpen;
  }

  @action
  setLook(group, value) {
    this.look = { ...(this.look ?? {}), ...this.style, [group]: value };
    saveLook(this.look);
  }

  @action
  resetLook() {
    this.look = null;
    saveLook(null);
  }

  get portalTarget() {
    return document.body;
  }

  <template>
    <section
      class="npn-exhibition {{this.wallClass}}"
      aria-label={{i18n "npn_submissions.exhibition.heading"}}
    >
      <header class="npn-exhibition__header">
        <h3 class="npn-exhibition__heading">
          {{i18n "npn_submissions.exhibition.heading"}}
          {{#if this.revisionNote}}
            <span class="npn-exhibition__revision">{{this.revisionNote}}</span>
          {{/if}}
        </h3>
        <div class="npn-exhibition__actions">
          <DButton
            @action={{this.startWalk}}
            @icon="play"
            @label="npn_submissions.exhibition.walk"
            class="btn-default btn-small"
          />
          <DButton
            @action={{this.toggleLook}}
            @icon="sliders"
            @label="npn_submissions.exhibition.try_look"
            aria-expanded={{if this.lookOpen "true" "false"}}
            class="btn-flat btn-small npn-exhibition__look-toggle"
          />
        </div>
      </header>

      {{#if this.lookOpen}}
        <div class="npn-exhibition__look">
          {{#each this.lookGroups as |group|}}
            <div
              class="npn-exhibition__look-group"
              role="group"
              aria-label={{group.heading}}
            >
              <span
                class="npn-exhibition__look-heading"
              >{{group.heading}}</span>
              {{#each group.options as |option|}}
                <button
                  type="button"
                  class="npn-exhibition__look-option
                    {{if option.active 'is-active'}}"
                  aria-pressed={{if option.active "true" "false"}}
                  {{on "click" (fn this.setLook option.group option.value)}}
                >
                  {{#if option.swatch}}
                    <span
                      class="npn-exhibition__swatch"
                      style={{option.swatch}}
                    ></span>
                  {{/if}}
                  {{option.label}}
                </button>
              {{/each}}
            </div>
          {{/each}}
          <p class="npn-exhibition__look-note">
            {{i18n "npn_submissions.exhibition.look.note"}}
            {{#if this.hasCustomLook}}
              <DButton
                @action={{this.resetLook}}
                @label="npn_submissions.exhibition.look.reset"
                class="btn-link npn-exhibition__look-reset"
              />
            {{/if}}
          </p>
        </div>
      {{/if}}

      <div class="npn-exhibition__wall" style={{this.mainWall.style}}>
        {{#each this.mainWall.prints as |print|}}
          <div
            class="npn-exhibition__frame
              {{if print.framed '--framed'}}
              {{if print.matted '--matted'}}"
            style={{print.frameStyle}}
          ></div>
          {{#if print.matted}}
            <div class="npn-exhibition__mat" style={{print.matStyle}}></div>
          {{/if}}
          <button
            type="button"
            class="npn-exhibition__print"
            style={{print.printStyle}}
            title={{print.title}}
            aria-label={{print.title}}
            {{on "click" (fn this.openPrint print.index)}}
          >
            <img src={{print.src}} alt={{print.label}} loading="lazy" />
          </button>
          <span
            class="npn-exhibition__placard"
            style={{print.placardStyle}}
            aria-hidden="true"
          >{{print.number}}</span>
        {{/each}}
      </div>

      {{#if this.alternateWall}}
        <div class="npn-exhibition__alternates">
          <h4 class="npn-exhibition__subheading">
            {{i18n "npn_submissions.exhibition.alternates"}}
          </h4>
          <div
            class="npn-exhibition__wall --alternates"
            style={{this.alternateWall.style}}
          >
            {{#each this.alternateWall.prints as |print|}}
              <div
                class="npn-exhibition__frame
                  {{if print.framed '--framed'}}
                  {{if print.matted '--matted'}}"
                style={{print.frameStyle}}
              ></div>
              {{#if print.matted}}
                <div class="npn-exhibition__mat" style={{print.matStyle}}></div>
              {{/if}}
              <button
                type="button"
                class="npn-exhibition__print"
                style={{print.printStyle}}
                title={{print.title}}
                aria-label={{print.title}}
                {{on "click" (fn this.openAlternate print.index)}}
              >
                <img src={{print.src}} alt={{print.label}} loading="lazy" />
              </button>
              <span
                class="npn-exhibition__placard --alternate"
                style={{print.placardStyle}}
                aria-hidden="true"
              >{{print.number}}</span>
            {{/each}}
          </div>
        </div>
      {{/if}}

      {{#if (notNull this.walkStart)}}
        {{#in-element this.portalTarget insertBefore=null}}
          <NpnWallWalk
            @images={{this.originals}}
            @style={{this.style}}
            @start={{this.walkStart}}
            @onClose={{this.endWalk}}
          />
        {{/in-element}}
      {{/if}}
    </section>
  </template>
}

function notNull(value) {
  return value !== null && value !== undefined;
}
