import Component from "@glimmer/component";
import { service } from "@ember/service";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

// Gentle, non-blocking notice shown beside a member-submitted photo when its
// uploaded file is over the downsample threshold. Guidance only: it never
// blocks upload, preview, or submission — it just explains that NPN may
// downsample larger files and that exporting a smaller JPEG first usually looks
// better.
//
// Deliberately opt-in: NpnImageList and the single-image upload areas only pass
// a filesize here for true photo contexts (Image Critique, Weekly Challenge,
// Project images/alternates, the project representative image, New Member and
// Introduction images). Support screenshots, metadata screenshots, PDFs, and
// other non-photo uploads never render it.
//
// Args:
//   @filesize - the upload's size in bytes (from the /uploads.json response).
//               May be undefined for restored-draft uploads, where size isn't
//               stored; in that case nothing is rendered (no crash, no warning).
export default class NpnLargeImageWarning extends Component {
  @service siteSettings;

  // Configurable threshold (MB). Shared with the image-spec copy so the warning
  // stays accurate if an admin changes the downsample threshold.
  get thresholdMb() {
    return (
      parseInt(this.siteSettings.npn_submissions_downsample_threshold_mb, 10) ||
      3
    );
  }

  get thresholdBytes() {
    return this.thresholdMb * 1024 * 1024;
  }

  // Only show for a real, known size over the threshold. A missing/NaN size
  // (restored drafts) is treated as "unknown" — stay quiet rather than guess.
  get isOver() {
    const size = this.args.filesize;
    return typeof size === "number" && size > this.thresholdBytes;
  }

  // The export/image-sizing guide. When blank, the link is hidden and only the
  // warning text shows.
  get exportGuideUrl() {
    return this.siteSettings.npn_submissions_export_guide_url;
  }

  <template>
    {{#if this.isOver}}
      <div class="npn-large-image-warning" role="note">
        <span class="npn-large-image-warning__text">
          {{dIcon "triangle-exclamation" class="npn-large-image-warning__icon"}}
          {{i18n
            "npn_submissions.form.images.large_warning"
            threshold=this.thresholdMb
          }}
        </span>
        {{#if this.exportGuideUrl}}
          <a
            class="npn-large-image-warning__link"
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
