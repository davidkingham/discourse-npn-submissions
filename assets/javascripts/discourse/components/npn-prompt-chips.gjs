import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { eq } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";

// "Feedback lenses" for the Feedback Requested textarea.
//
// `@chips` is an array of { key, label, prompt, suggested }; `@onPick`
// receives the `suggested` text when the user opts in via the panel's
// secondary action.
//
// Two voices live in each panel:
//   - `prompt` is the reflective question, spoken TO the poster ("What
//     feeling did you hope the image would create?"). It's guidance for
//     thinking and is never written to the textarea.
//   - `suggested` is a sentence written FROM the poster's point of view
//     ("I'm wondering whether the mood I was aiming for comes through.").
//     This is the only string that can ever reach the textarea, and only
//     when the user clicks "Add suggested wording".
//
// Click behaviour:
//   - Clicking a chip toggles the inline panel below the chip row. It does
//     NOT write to the textarea.
//   - Inside the panel, "Add suggested wording" passes `chip.suggested` to
//     `@onPick`. The parent appends it after a blank line, never overwriting.
//
// Focus changes are handled by the parent (the chip list reference changes
// when Feedback Focus changes). `selectedChip` resolves the open key against
// the *current* chip list, so a key that no longer exists resolves to null
// and the panel collapses — without ever touching the user's typed
// Feedback Requested text.
export default class NpnPromptChips extends Component {
  @tracked selectedKey = null;

  get selectedChip() {
    const key = this.selectedKey;
    if (!key) {
      return null;
    }
    return (this.args.chips || []).find((c) => c.key === key) || null;
  }

  @action
  togglePanel(key) {
    this.selectedKey = this.selectedKey === key ? null : key;
  }

  @action
  insertSelected() {
    const chip = this.selectedChip;
    if (chip?.suggested && this.args.onPick) {
      this.args.onPick(chip.suggested);
    }
  }

  <template>
    <div class="npn-prompt-chips">
      <div class="npn-prompt-chips__heading">
        <span class="npn-prompt-chips__intro">
          {{i18n "npn_submissions.form.chips.intro"}}
        </span>
        <span class="npn-prompt-chips__help">
          {{i18n "npn_submissions.form.chips.help"}}
        </span>
      </div>
      <div class="npn-prompt-chips__buttons" role="group">
        {{#each @chips as |chip|}}
          <button
            type="button"
            class="npn-chip
              {{if (eq this.selectedKey chip.key) 'is-selected'}}"
            aria-expanded={{if (eq this.selectedKey chip.key) "true" "false"}}
            {{on "click" (fn this.togglePanel chip.key)}}
          >{{chip.label}}</button>
        {{/each}}
      </div>
      {{#if this.selectedChip}}
        <div
          class="npn-prompt-chips__panel"
          role="region"
          aria-label={{this.selectedChip.label}}
        >
          <div class="npn-prompt-chips__section">
            <span class="npn-prompt-chips__section-label">
              {{i18n "npn_submissions.form.chips.think_about"}}
            </span>
            <p class="npn-prompt-chips__prompt">
              {{this.selectedChip.prompt}}
            </p>
          </div>
          <div class="npn-prompt-chips__section">
            <span class="npn-prompt-chips__section-label">
              {{i18n "npn_submissions.form.chips.suggested_label"}}
            </span>
            <p class="npn-prompt-chips__suggested">
              {{this.selectedChip.suggested}}
            </p>
          </div>
          <div class="npn-prompt-chips__panel-actions">
            <DButton
              @label="npn_submissions.form.chips.insert"
              @action={{this.insertSelected}}
              class="btn-flat btn-small npn-prompt-chips__insert"
            />
            <span class="npn-prompt-chips__insert-help">
              {{i18n "npn_submissions.form.chips.insert_help"}}
            </span>
          </div>
        </div>
      {{/if}}
    </div>
  </template>
}
