import Component from "@glimmer/component";
import { service } from "@ember/service";
import { i18n } from "discourse-i18n";

// Renders an "Ask for Help" call-to-action button next to the d-navigation
// Create Topic button — but only when the user is looking at the configured
// Help category. The default Create Topic button is already hidden in this
// category via the managed-category mechanism (admin adds the category id
// to `npn_submissions_managed_category_ids`), so this CTA effectively
// replaces the default button in the same spot.
//
// Parallel to npn-introduction-cta / npn-new-member-image-cta — multiple
// connectors live at the same outlet and each filters on its own category
// id, so at most one renders per page.
export default class NpnHelpCta extends Component {
  static shouldRender(args, context) {
    const settings =
      context.siteSettings || context.owner?.lookup?.("service:site-settings");
    if (!settings?.npn_submissions_enabled) {
      return false;
    }
    const configured = parseInt(settings.npn_submissions_help_category_id, 10);
    if (!Number.isInteger(configured) || configured <= 0) {
      return false;
    }
    return args.category?.id === configured;
  }

  @service currentUser;

  get show() {
    return !!this.currentUser?.can_npn_submit;
  }

  <template>
    {{#if this.show}}
      <a href="/submit?type=help" class="btn btn-primary npn-help-cta">
        {{i18n "npn_submissions.help.cta_button"}}
      </a>
    {{/if}}
  </template>
}
