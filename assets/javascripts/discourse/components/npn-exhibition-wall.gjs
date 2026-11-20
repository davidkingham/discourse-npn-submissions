import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import { openProjectViewer } from "../lib/npn-project-viewer";
import {
  aspectOf,
  formatWallWidth,
  layoutWall,
  resolveHang,
  resolveOrders,
} from "../lib/npn-wall-layout";
import NpnHangWall from "./npn-hang-wall";
import NpnWallWalk from "./npn-wall-walk";

function narrowScreen() {
  return window.matchMedia?.("(max-width: 600px)")?.matches ?? false;
}

// The photographer's hang at the top of a project's original post: every
// print framed, matted and numbered at its real size, on their chosen wall,
// with a floor line and bench for scale. Tap a print to see it large; "Walk
// the wall" opens a full-screen walk. Alternates hang on a separate panel
// at the same scale. Posts without a saved hang (older posts) get the
// presentation goal's default look.
//
// @data: { images } — the topic's npn_project_images.
export default class NpnExhibitionWall extends Component {
  @tracked walkStart = null;
  // Which of the photographer's proposed orders is on the wall (0 = main).
  @tracked activeOrder = 0;

  get images() {
    return this.args.data?.images ?? {};
  }

  get originals() {
    return this.images.originals ?? [];
  }

  get alternates() {
    return this.images.alternates ?? [];
  }

  // The photographer's main order plus any alternatives they proposed.
  get orders() {
    return resolveOrders(this.images.hang, this.images.intent, this.originals);
  }

  get orderTabs() {
    const orders = this.orders;
    if (orders.length < 2) {
      return [];
    }
    const active = Math.min(this.activeOrder, orders.length - 1);
    return orders.map((order, index) => ({
      index,
      name: order.name,
      active: index === active,
    }));
  }

  // The prints in the order on the wall. Their numbers stay the main
  // order's, so an alternative reads "9, 8, 7 …".
  get prints() {
    const orders = this.orders;
    const order = orders[Math.min(this.activeOrder, orders.length - 1)];
    return order.indexes.map((i) => this.originals[i]);
  }

  @action
  showOrder(index) {
    this.activeOrder = index;
  }

  get hang() {
    const hang = resolveHang(
      this.images.hang,
      this.images.intent,
      this.prints,
      [...this.originals, ...this.alternates]
    );
    // A book: two spreads per row on a phone.
    if (hang.mode === "spreads") {
      return narrowScreen() ? { ...hang, perRow: 2 } : hang;
    }
    // On a phone, more than three prints in one line (or beside a lead
    // print) are too small to read: hang rows of three instead.
    if (narrowScreen() && this.originals.length > 3) {
      return { ...hang, layout: "rows", perRow: 3 };
    }
    return hang;
  }

  get mainWall() {
    return layoutWall(this.prints.map(aspectOf), this.hang);
  }

  get widthLabel() {
    return this.hang.physical
      ? formatWallWidth(this.mainWall.hangWidth, this.hang.unit)
      : null;
  }

  // Alternates: their own sizes (from the hang, by upload id), shown on a
  // plain panel at the same scale as the main wall.
  get alternateHang() {
    const sized = resolveHang(
      this.images.hang,
      this.images.intent,
      this.alternates
    );
    // Always a plain line of images, whatever the project's own layout.
    return { ...sized, mode: "sequence", layout: "line", physical: false };
  }

  get alternateWidthPercent() {
    // A book is measured in pages, not inches: just keep the panel modest.
    if (this.hang.mode === "spreads") {
      return Math.min(100, 20 * this.alternates.length + 10);
    }
    const wall = layoutWall(this.alternates.map(aspectOf), this.alternateHang);
    return Math.min(100, (wall.width / this.mainWall.width) * 100);
  }

  get headingText() {
    return i18n(`npn_submissions.exhibition.headings.${this.hang.mode}`);
  }

  // A physical hang or a web page is something you walk along; a book,
  // magazine or selection is just viewed in order.
  get walkLabel() {
    const mode = this.hang.mode;
    return mode === "hang" || mode === "page"
      ? "npn_submissions.exhibition.walk"
      : "npn_submissions.exhibition.view_in_order";
  }

  get revisionNote() {
    const revision = this.images.revision;
    return revision
      ? i18n("npn_submissions.exhibition.revision_note", { revision })
      : null;
  }

  get portalTarget() {
    return document.body;
  }

  get walking() {
    return this.walkStart !== null;
  }

  @action
  openPrint(index) {
    openProjectViewer(this.prints, index);
  }

  @action
  openAlternate(index) {
    openProjectViewer(this.alternates, index);
  }

  @action
  startWalk() {
    // A book is paged through in order rather than walked like a wall.
    if (this.hang.mode === "spreads") {
      openProjectViewer(this.prints, 0);
      return;
    }
    this.walkStart = 0;
  }

  @action
  endWalk() {
    this.walkStart = null;
  }

  <template>
    <section class="npn-exhibition" aria-label={{this.headingText}}>
      <header class="npn-exhibition__header">
        <h3 class="npn-exhibition__heading">
          {{this.headingText}}
          {{#if this.revisionNote}}
            <span class="npn-exhibition__revision">{{this.revisionNote}}</span>
          {{/if}}
        </h3>
        <div class="npn-exhibition__actions">
          {{#if this.widthLabel}}
            <span class="npn-exhibition__width">
              {{i18n
                "npn_submissions.exhibition.hang_width"
                width=this.widthLabel
              }}
            </span>
          {{/if}}
          <DButton
            @action={{this.startWalk}}
            @icon="play"
            @label={{this.walkLabel}}
            class="btn-default btn-small"
          />
        </div>
      </header>

      {{#if this.orderTabs.length}}
        <div
          class="npn-exhibition__orders"
          role="group"
          aria-label={{i18n "npn_submissions.orders.tabs"}}
        >
          <span class="npn-exhibition__orders-label">
            {{i18n "npn_submissions.orders.tabs"}}
          </span>
          {{#each this.orderTabs as |tab|}}
            <button
              type="button"
              class="npn-exhibition__order {{if tab.active 'is-active'}}"
              aria-pressed={{if tab.active "true" "false"}}
              {{on "click" (fn this.showOrder tab.index)}}
            >{{tab.name}}</button>
          {{/each}}
        </div>
      {{/if}}

      <NpnHangWall
        @images={{this.prints}}
        @hang={{this.hang}}
        @onPrint={{this.openPrint}}
      />

      {{#if this.alternates.length}}
        <div class="npn-exhibition__alternates">
          <h4 class="npn-exhibition__subheading">
            {{i18n "npn_submissions.exhibition.alternates"}}
          </h4>
          <NpnHangWall
            @images={{this.alternates}}
            @hang={{this.alternateHang}}
            @widthPercent={{this.alternateWidthPercent}}
            @onPrint={{this.openAlternate}}
          />
        </div>
      {{/if}}

      {{#if this.walking}}
        {{#in-element this.portalTarget insertBefore=null}}
          <NpnWallWalk
            @images={{this.prints}}
            @hang={{this.hang}}
            @start={{this.walkStart}}
            @onClose={{this.endWalk}}
          />
        {{/in-element}}
      {{/if}}
    </section>
  </template>
}
