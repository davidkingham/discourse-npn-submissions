import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

// Ideas for a member who doesn't know what to ask, kept below the writing box
// and closed until wanted: writing in their own words comes first.
//
// `@ideas` is [{ key, text }]. Each idea is shown as the sentence itself, and
// tapping it does the one thing it looks like it does: adds that sentence to
// the box (`@onPick`), where it can be edited. Nothing is selected or stored.
export default class NpnAskIdeas extends Component {
  @tracked added = [];

  get rows() {
    return (this.args.ideas || []).map((idea) => ({
      idea,
      added: this.added.includes(idea.key),
    }));
  }

  @action
  add(idea) {
    this.args.onPick?.(idea.text);
    if (!this.added.includes(idea.key)) {
      this.added = [...this.added, idea.key];
    }
  }

  <template>
    <details class="npn-ask-ideas">
      <summary>{{@summary}}</summary>
      <div class="npn-ask-ideas__body">
        <p class="npn-ask-ideas__help">
          {{i18n "npn_submissions.photo_form.ideas.help"}}
        </p>
        <ul class="npn-ask-ideas__list">
          {{#each this.rows key="idea.key" as |row|}}
            <li>
              <button
                type="button"
                class="npn-ask-ideas__idea {{if row.added 'is-added'}}"
                {{on "click" (fn this.add row.idea)}}
              >
                <span class="npn-ask-ideas__text">{{row.idea.text}}</span>
                <span class="npn-ask-ideas__action">
                  {{#if row.added}}
                    {{dIcon "check"}}
                    {{i18n "npn_submissions.photo_form.ideas.added"}}
                  {{else}}
                    {{dIcon "plus"}}
                    {{i18n "npn_submissions.photo_form.ideas.add"}}
                  {{/if}}
                </span>
              </button>
            </li>
          {{/each}}
        </ul>
      </div>
    </details>
  </template>
}
