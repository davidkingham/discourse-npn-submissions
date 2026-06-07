# frozen_string_literal: true

module DiscourseNpnSubmissions
  # Builds the Markdown body of the topic created from a New Members Area
  # image submission — a gentle, low-pressure way for newer members to share
  # one nature image and invite basic feedback before they're ready for the
  # full Image Critique categories.
  #
  # Kept separate from the critique/project/introduction builders because the
  # layout is intentionally minimal: just the image, then an optional `About
  # This Image` section, then an optional `Feedback Welcome` section. No
  # critique guidance card, no feedback focus, no weekly callout, no project
  # overview, no technical details, no markers.
  #
  # Field key convention (matches Submission#field):
  #   - `about_this_image` — optional, becomes the body of "About This Image"
  #     (reuses the established critique field key so future cross-form
  #     tooling reads consistently)
  #   - `feedback`          — optional, becomes the body of "Feedback Welcome"
  #                           (deliberately distinct from the critique
  #                           `feedback_requested` key — the heading is
  #                           softer and the contracts shouldn't be confused)
  module NewMemberImagePostBuilder
    ABOUT_HEADING = "About This Image"
    FEEDBACK_HEADING = "Feedback Welcome"

    module_function

    def build(submission)
      parts = []
      parts << image_block(submission)
      parts << section(ABOUT_HEADING, submission.field("about_this_image"))
      parts << section(FEEDBACK_HEADING, submission.field("feedback"))
      parts.reject(&:blank?).join("\n\n").strip
    end

    # The required single image. Rendered as a normal Markdown image so
    # Discourse cooks it as usual (and wires the standard lightbox). Alt
    # text uses the topic title, falling back to a generic label so the
    # alt attribute is never empty.
    def image_block(submission)
      upload = submission.main_upload
      return nil unless upload

      alt = submission.title.to_s.strip.presence || "Image"
      "![#{alt}](#{upload.short_url})"
    end

    def section(heading, body)
      stripped = body.to_s.strip
      return nil if stripped.blank?
      "### #{heading}\n\n#{stripped}"
    end
  end
end
