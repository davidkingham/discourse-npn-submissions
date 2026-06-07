import Component from "@glimmer/component";
import { service } from "@ember/service";
import { i18n } from "discourse-i18n";

// Renders an "Introduce Yourself" call-to-action button next to the
// d-navigation Create Topic button — but only when the user is looking at the
// configured Introduction category, AND only when the user can submit through
// this plugin. The default Create Topic button is already hidden in this
// category via the managed-category mechanism (admin adds the introduction
// category to `npn_submissions_managed_category_ids`), so this CTA
// effectively replaces the default button in the same spot.
//
// Outlet args (from d-navigation): { category, tag, canCreateTopic,
// createTopicDisabled, createTopicLabel }. We only need `category` here.
//
// Graceful degradation: if the outlet ever moves in core, the connector
// silently no-ops; the rest of the introduction flow keeps working (the
// chooser page at /submit still lists Introduction).
export default class NpnIntroductionCta extends Component {
  // Connector-component pattern: classmethod check. Returns true only inside
  // the configured introduction category.
  static shouldRender(args, context) {
    const settings =
      context.siteSettings || context.owner?.lookup?.("service:site-settings");
    if (!settings?.npn_submissions_enabled) {
      return false;
    }
    const configured = parseInt(
      settings.npn_submissions_introduction_category_id,
      10
    );
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
      <a
        href="/submit?type=introduction"
        class="btn btn-primary npn-introduction-cta"
      >
        {{i18n "npn_submissions.introduction.cta_button"}}
      </a>
    {{/if}}
  </template>
}
