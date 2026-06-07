import Component from "@glimmer/component";
import { service } from "@ember/service";
import { i18n } from "discourse-i18n";

// Renders a "Share an Image" call-to-action button next to the d-navigation
// Create Topic button — but only when the user is looking at the configured
// New Members Area image category. The default Create Topic button is
// already hidden in this category via the managed-category mechanism
// (admin adds the category id to `npn_submissions_managed_category_ids`),
// so this CTA effectively replaces the default button in the same spot.
//
// Mirror of npn-introduction-cta — both connectors live at the same outlet
// and each filters on its own category id, so at most one renders per page.
//
// Graceful degradation: if the outlet ever moves in core, the connector
// silently no-ops; the rest of the new-member-image flow keeps working (the
// /submit chooser still lists it).
export default class NpnNewMemberImageCta extends Component {
  static shouldRender(args, context) {
    const settings =
      context.siteSettings || context.owner?.lookup?.("service:site-settings");
    if (!settings?.npn_submissions_enabled) {
      return false;
    }
    const configured = parseInt(
      settings.npn_submissions_new_member_image_category_id,
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
        href="/submit?type=new_member_image"
        class="btn btn-primary npn-new-member-image-cta"
      >
        {{i18n "npn_submissions.new_member_image.cta_button"}}
      </a>
    {{/if}}
  </template>
}
