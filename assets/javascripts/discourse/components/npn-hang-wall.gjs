import Component from "@glimmer/component";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { trustHTML } from "@ember/template";
import { i18n } from "discourse-i18n";
import { RANKS } from "../lib/npn-hang-suggestion";
import {
  aspectOf,
  formatPrintSize,
  FRAMES,
  layoutWall,
  MATS,
  percentRect,
  WALLS,
} from "../lib/npn-wall-layout";

function pct(value) {
  return `${Math.round(value * 1000) / 1000}%`;
}

function rectStyle(rect, wall) {
  const p = percentRect(rect, wall);
  return `left:${pct(p.left)};top:${pct(p.top)};width:${pct(p.width)};height:${pct(p.height)};`;
}

// Draws one hang: the wall, a floor line and bench for scale (physical
// walls), and every print framed, matted and numbered at its real size.
// Shared by the hang editor in the project form, the exhibition wall on the
// post, and (later) a critic's suggested hang.
//
// @images     prints in hanging order ({ number, url, sheet_url, width, … })
// @hang       a resolved hang (lib/npn-wall-layout resolveHang)
// @widthPercent  optional: width of this wall relative to its container
// @onPrint    (index, event) => void — a print was clicked
// @marks      optional { number: "strongest" | "keep" | "unsure" } — a
//             critic's ranking, shown before the placard number
// @editable   show resize grips and size labels
// @selected   Set of selected indexes (editable)
// Resize grips (.npn-hang-wall__grip, in print order) are handled by the
// parent with a delegated pointerdown listener.
export default class NpnHangWall extends Component {
  get images() {
    return this.args.images ?? [];
  }

  get hang() {
    return this.args.hang;
  }

  get layout() {
    return layoutWall(this.images.map(aspectOf), this.hang);
  }

  get wallColors() {
    return WALLS[this.hang.wall];
  }

  get wallStyle() {
    const wall = this.layout;
    const width = this.args.widthPercent ?? 100;
    return trustHTML(
      `aspect-ratio:${wall.width} / ${wall.height};` +
        `background-color:${this.wallColors.color};width:${pct(width)};`
    );
  }

  get floorStyle() {
    const wall = this.layout;
    if (wall.floorY === undefined) {
      return null;
    }
    return trustHTML(
      `top:${pct((wall.floorY / wall.height) * 100)};background-color:${this.wallColors.floor};`
    );
  }

  get benchStyle() {
    const wall = this.layout;
    return wall.bench ? trustHTML(rectStyle(wall.bench, wall)) : null;
  }

  get prints() {
    const wall = this.layout;
    const mat = MATS[this.hang.mat];
    const frame = FRAMES[this.hang.frame];
    const selected = this.args.selected;
    const total = this.images.filter((i) => !i.number?.startsWith("A")).length;
    return wall.boxes.map((b) => {
      const image = this.images[b.index];
      const isAlternate = image.number?.startsWith("A");
      const label = isAlternate
        ? i18n("npn_submissions.exhibition.alternate_label", {
            number: image.number.slice(1),
          })
        : i18n("npn_submissions.exhibition.image_label", {
            number: image.number,
            total,
          });
      const size = this.hang.sizes?.[b.index];
      const rank = RANKS.find((r) => r.key === this.args.marks?.[image.number]);
      return {
        index: b.index,
        image,
        label,
        title: image.caption ? `${label}: ${image.caption}` : label,
        src: image.sheet_url || image.url,
        number: image.number,
        isAlternate,
        mark: rank ? rank.symbol : null,
        markStyle: rank ? trustHTML(`color:${rank.color}`) : null,
        selected: selected?.has?.(b.index) ?? false,
        sizeLabel:
          this.hang.physical && size
            ? formatPrintSize(size, aspectOf(image), this.hang.unit)
            : null,
        frameStyle: trustHTML(
          rectStyle(b, wall) +
            `background-color:${frame || mat || "transparent"};`
        ),
        matStyle: mat
          ? trustHTML(
              rectStyle(
                {
                  x: b.x + b.frame,
                  y: b.y + b.frame,
                  w: b.w - b.frame * 2,
                  h: b.h - b.frame * 2,
                },
                wall
              ) + `background-color:${mat};`
            )
          : null,
        printStyle: trustHTML(rectStyle(b.print, wall)),
        placardStyle: trustHTML(
          rectStyle({ x: b.x, y: b.placardY, w: b.w, h: 3 }, wall)
        ),
        gripStyle: trustHTML(
          `left:${pct(((b.x + b.w) / wall.width) * 100)};top:${pct(((b.y + b.h) / wall.height) * 100)};`
        ),
        framed: !!frame,
        matted: !!mat,
      };
    });
  }

  <template>
    <div
      class="npn-hang-wall
        {{if this.wallColors.dark '--dark-wall' '--light-wall'}}
        {{if @editable '--editable'}}"
      style={{this.wallStyle}}
    >
      {{#if this.floorStyle}}
        <div class="npn-hang-wall__floor" style={{this.floorStyle}}></div>
      {{/if}}
      {{#if this.benchStyle}}
        <svg
          class="npn-hang-wall__bench"
          style={{this.benchStyle}}
          viewBox="0 0 48 18"
          preserveAspectRatio="none"
          aria-hidden="true"
        >
          <rect x="0" y="0" width="48" height="3" rx="0.5" />
          <rect x="3" y="3" width="2.5" height="15" />
          <rect x="42.5" y="3" width="2.5" height="15" />
        </svg>
      {{/if}}

      {{#each this.prints as |print|}}
        <div
          class="npn-hang-wall__frame
            {{if print.framed '--framed'}}
            {{if print.matted '--matted'}}"
          style={{print.frameStyle}}
        ></div>
        {{#if print.matStyle}}
          <div class="npn-hang-wall__mat" style={{print.matStyle}}></div>
        {{/if}}
        <button
          type="button"
          class="npn-hang-wall__print {{if print.selected 'is-selected'}}"
          style={{print.printStyle}}
          title={{print.title}}
          aria-label={{print.title}}
          aria-pressed={{if @editable (if print.selected "true" "false")}}
          {{on "click" (fn @onPrint print.index)}}
        >
          <img
            src={{print.src}}
            alt={{print.label}}
            loading="lazy"
            draggable="false"
          />
          {{#if @editable}}
            {{#if print.sizeLabel}}
              <span class="npn-hang-wall__size">{{print.sizeLabel}}</span>
            {{/if}}
          {{/if}}
        </button>
        <span
          class="npn-hang-wall__placard {{if print.isAlternate '--alternate'}}"
          style={{print.placardStyle}}
          aria-hidden="true"
        >{{#if print.mark}}<span
              class="npn-hang-wall__mark"
              style={{print.markStyle}}
            >{{print.mark}}</span>{{/if}}{{print.number}}</span>
        {{#if @editable}}
          {{#if this.hang.physical}}
            <span
              class="npn-hang-wall__grip"
              style={{print.gripStyle}}
              role="presentation"
              title={{i18n "npn_submissions.hang.grip"}}
            ></span>
          {{/if}}
        {{/if}}
      {{/each}}
    </div>
  </template>
}
