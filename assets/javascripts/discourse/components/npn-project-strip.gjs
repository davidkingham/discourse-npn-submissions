import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import { numberLabel } from "../lib/npn-sequence";

const COLLAPSED_KEY = "npn_project_strip_collapsed";

// A compact, numbered thumbnail strip of the project's images pinned at the top
// of the reply composer, so critics can refer to "Image 4" without scrolling
// back up the topic. Also the most visible entry point to the
// Suggest-a-Sequence builder. Collapsible; the choice is remembered per
// browser.
export default class NpnProjectStrip extends Component {
  @service keyValueStore;
  @service npnSequenceBuilder;

  @tracked collapsed = this.keyValueStore.get(COLLAPSED_KEY) === "true";

  get images() {
    if (this.args.model?.action !== "reply") {
      return null;
    }
    return this.npnSequenceBuilder.imagesFor(this.args.model?.topic);
  }

  get tiles() {
    const images = this.images;
    if (!images) {
      return [];
    }
    return [...images.originals, ...(images.alternates ?? [])].map((image) => ({
      image,
      src: image.sheet_url || image.url,
      label: numberLabel(image.number),
      title: image.caption
        ? `${numberLabel(image.number)}: ${image.caption}`
        : numberLabel(image.number),
      isAlternate: image.number.startsWith("A"),
    }));
  }

  @action
  toggle() {
    this.collapsed = !this.collapsed;
    this.keyValueStore.set({
      key: COLLAPSED_KEY,
      value: String(this.collapsed),
    });
  }

  get suggestLabel() {
    return this.npnSequenceBuilder.buttonLabelFor(this.images);
  }

  @action
  openBuilder() {
    this.npnSequenceBuilder.open({
      images: this.images,
      onInsert: (markup, label) =>
        this.npnSequenceBuilder.insertIntoComposer(markup, label),
    });
  }

  <template>
    {{#if this.images}}
      <div class="npn-project-strip {{if this.collapsed 'is-collapsed'}}">
        <div class="npn-project-strip__head">
          <span class="npn-project-strip__title">
            {{i18n "npn_submissions.sequence.strip_title"}}
          </span>
          <DButton
            @action={{this.openBuilder}}
            @icon="film"
            @label={{this.suggestLabel}}
            class="btn-default btn-small npn-project-strip__suggest"
          />
          <DButton
            @action={{this.toggle}}
            @label={{if
              this.collapsed
              "npn_submissions.sequence.strip_show"
              "npn_submissions.sequence.strip_hide"
            }}
            class="btn-flat btn-small npn-project-strip__toggle"
          />
        </div>
        {{#unless this.collapsed}}
          <div class="npn-project-strip__tiles">
            {{#each this.tiles as |tile|}}
              <figure
                class="npn-project-strip__tile
                  {{if tile.isAlternate 'is-alternate'}}"
                title={{tile.title}}
              >
                <img src={{tile.src}} alt={{tile.label}} loading="lazy" />
                <figcaption>{{tile.label}}</figcaption>
              </figure>
            {{/each}}
          </div>
        {{/unless}}
      </div>
    {{/if}}
  </template>
}
