import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { i18n } from "discourse-i18n";

// Clickable chips that insert a starter question into a field. `@chips` is an
// array of { label, text }; `@onPick` receives the chosen text.
const NpnPromptChips = <template>
  <div class="npn-chips">
    <span class="npn-chips__intro">{{i18n "npn_submissions.form.chips.intro"}}</span>
    {{#each @chips as |chip|}}
      <button
        type="button"
        class="npn-chip"
        {{on "click" (fn @onPick chip.text)}}
      >{{chip.label}}</button>
    {{/each}}
  </div>
</template>;

export default NpnPromptChips;
