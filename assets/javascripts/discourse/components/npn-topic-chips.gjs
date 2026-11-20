import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";

// Tappable prompts above a writing box in the photo-first form.
//
// `@chips` is [{ key, label, prompt, suggested }]. Tapping a chip opens a small
// panel with a question to think about and a line of suggested wording, which
// only reaches the box through "Add this wording" (`@onPick`).
//
// With `@onToggle` the chips are also a selection: a tapped chip stays lit and
// the parent hears about it (the image form reads the selection to work out
// the feedback focus). Without it they are prompts only.
export default class NpnTopicChips extends Component {
  @tracked openKey = null;

  get rows() {
    const selected = this.args.selected || [];
    return (this.args.chips || []).map((chip) => ({
      chip,
      selected: selected.includes(chip.key),
      open: this.openKey === chip.key,
    }));
  }

  get openChip() {
    return (this.args.chips || []).find((chip) => chip.key === this.openKey);
  }

  get selectable() {
    return !!this.args.onToggle;
  }

  @action
  tap(row) {
    if (!this.selectable) {
      this.openKey = row.open ? null : row.chip.key;
      return;
    }
    // Selecting opens the chip's panel; tapping a lit chip puts it out.
    this.openKey = row.selected ? null : row.chip.key;
    this.args.onToggle(row.chip.key);
  }

  @action
  addWording() {
    if (this.openChip?.suggested) {
      this.args.onPick?.(this.openChip.suggested);
    }
  }

  <template>
    <div class="npn-topic-chips">
      {{#if @intro}}
        <p class="npn-topic-chips__intro">{{@intro}}</p>
      {{/if}}
      <div class="npn-topic-chips__buttons" role="group" aria-label={{@intro}}>
        {{#each this.rows key="chip.key" as |row|}}
          <button
            type="button"
            class="npn-topic-chip
              {{if row.selected 'is-selected'}}
              {{if row.open 'is-open'}}"
            aria-pressed={{if this.selectable (if row.selected "true" "false")}}
            aria-expanded={{if row.open "true" "false"}}
            {{on "click" (fn this.tap row)}}
          >{{row.chip.label}}</button>
        {{/each}}
      </div>
      {{#if this.openChip}}
        <div class="npn-topic-chips__panel">
          <p class="npn-topic-chips__prompt">{{this.openChip.prompt}}</p>
          <p class="npn-topic-chips__suggested">
            {{this.openChip.suggested}}
          </p>
          <DButton
            @translatedLabel={{i18n "npn_submissions.photo_form.chips.add"}}
            @icon="plus"
            @action={{this.addWording}}
            class="btn-flat btn-small npn-topic-chips__add"
          />
        </div>
      {{/if}}
    </div>
  </template>
}
