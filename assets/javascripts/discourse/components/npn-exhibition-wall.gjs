import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import { openProjectViewer } from "../lib/npn-project-viewer";
import {
  aspectOf,
  formatWallWidth,
  layoutWall,
  resolveHang,
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

  get images() {
    return this.args.data?.images ?? {};
  }

  get originals() {
    return this.images.originals ?? [];
  }

  get alternates() {
    return this.images.alternates ?? [];
  }

  get hang() {
    const hang = resolveHang(
      this.images.hang,
      this.images.intent,
      this.originals
    );
    // On a phone, more than three prints in one line (or beside a lead
    // print) are too small to read: hang rows of three instead.
    if (narrowScreen() && this.originals.length > 3) {
      return { ...hang, layout: "rows", perRow: 3 };
    }
    return hang;
  }

  get mainWall() {
    return layoutWall(this.originals.map(aspectOf), this.hang);
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
    return { ...sized, layout: "line", physical: false };
  }

  get alternateWidthPercent() {
    const wall = layoutWall(this.alternates.map(aspectOf), this.alternateHang);
    return Math.min(100, (wall.width / this.mainWall.width) * 100);
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

  <template>
    <section
      class="npn-exhibition"
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
            @label="npn_submissions.exhibition.walk"
            class="btn-default btn-small"
          />
        </div>
      </header>

      <NpnHangWall
        @images={{this.originals}}
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
            @images={{this.originals}}
            @hang={{this.hang}}
            @start={{this.walkStart}}
            @onClose={{this.endWalk}}
          />
        {{/in-element}}
      {{/if}}
    </section>
  </template>
}
