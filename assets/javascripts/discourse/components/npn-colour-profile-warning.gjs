import Component from "@glimmer/component";
import { service } from "@ember/service";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import { colourProfileWarningFor } from "../lib/npn-colour-profile";

// Gentle, non-blocking notice shown beside a member-submitted photo whose file
// is in ProPhoto RGB or a colour profile we don't recognise. Those files do not
// look the same in every view (see lib/npn-colour-profile.js), so we say so
// and point at the export guide. Guidance only: it never blocks upload,
// preview, or submission.
//
// Rendered next to NpnLargeImageWarning, in the same true-photo contexts.
//
// Args:
//   @upload - the /uploads.json response for the photo. The profile is noted
//             against it when the file is uploaded (noteColourProfile);
//             restored-draft uploads have none, so nothing is rendered.
export default class NpnColourProfileWarning extends Component {
  @service siteSettings;

  get profileName() {
    return colourProfileWarningFor(this.args.upload);
  }

  get messageKey() {
    return this.siteSettings.npn_submissions_convert_uploads_to_srgb
      ? "npn_submissions.form.images.colour_profile_converted"
      : "npn_submissions.form.images.colour_profile_warning";
  }

  get exportGuideUrl() {
    return this.siteSettings.npn_submissions_export_guide_url;
  }

  <template>
    {{#if this.profileName}}
      <div class="npn-colour-profile-warning" role="note">
        <span class="npn-colour-profile-warning__text">
          {{dIcon
            "triangle-exclamation"
            class="npn-colour-profile-warning__icon"
          }}
          {{i18n this.messageKey profile=this.profileName}}
        </span>
        {{#if this.exportGuideUrl}}
          <a
            class="npn-colour-profile-warning__link"
            href={{this.exportGuideUrl}}
            target="_blank"
            rel="noopener noreferrer"
          >
            {{i18n "npn_submissions.form.images.large_warning_link"}}
          </a>
        {{/if}}
      </div>
    {{/if}}
  </template>
}
