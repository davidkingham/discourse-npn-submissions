import Component from "@glimmer/component";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";

// Subtle autosave status shown near the form actions. Quiet and unobtrusive;
// hidden until the first autosave happens.
export default class NpnAutosaveStatus extends Component {
  get status() {
    return this.args.autosaver?.status;
  }

  get visible() {
    return this.status && this.status !== "idle";
  }

  get label() {
    const autosaver = this.args.autosaver;
    switch (this.status) {
      case "saving":
        return i18n("npn_submissions.form.autosave.saving");
      case "failed":
        return i18n("npn_submissions.form.autosave.failed");
      case "saved": {
        const minutes = autosaver.minutesSinceSave;
        return minutes < 1
          ? i18n("npn_submissions.form.autosave.saved_now")
          : i18n("npn_submissions.form.autosave.saved_ago", { count: minutes });
      }
      default:
        return "";
    }
  }

  <template>
    {{#if this.visible}}
      <p
        class="npn-autosave-status {{if (eq this.status 'failed') 'is-failed'}}"
        aria-live="polite"
      >{{this.label}}</p>
    {{/if}}
  </template>
}
