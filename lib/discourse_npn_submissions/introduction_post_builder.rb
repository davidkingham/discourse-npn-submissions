# frozen_string_literal: true

module DiscourseNpnSubmissions
  # Builds the Markdown body of the topic created from a New Member
  # Introduction submission. Kept separate from PostBuilder / ProjectPostBuilder
  # because the introduction layout is intentionally minimal and welcoming —
  # none of the critique guidance card, feedback focus, weekly challenge
  # callout, technical details, project overview grid, marker comments, etc.
  #
  # Layout: optional image first (so it lands near the title visually), then
  # an `### About Me` section, then an optional `### What I'm Hoping to Learn
  # or Explore` section. Blank optional pieces are omitted entirely.
  #
  # Field key convention (matches Submission#field):
  #   - `about`    — required free text, becomes the body of "About Me"
  #   - `learning` — optional, becomes the body of the learning section when
  #                  present
  module IntroductionPostBuilder
    ABOUT_HEADING = "About Me"
    LEARNING_HEADING = "What I’m Hoping to Learn or Explore"

    module_function

    def build(submission)
      parts = []
      parts << image_block(submission)
      parts << section(ABOUT_HEADING, submission.field("about"))
      parts << section(LEARNING_HEADING, submission.field("learning"))
      parts.reject(&:blank?).join("\n\n").strip
    end

    # At most one image — the form caps the user to a single optional upload.
    # Rendered as a normal Markdown image so Discourse cooks it as usual and
    # wires the standard lightbox. Alt text uses the topic title.
    def image_block(submission)
      upload = submission.main_upload
      return nil unless upload

      alt = submission.title.to_s.strip.presence || "Introduction image"
      "![#{alt}](#{upload.short_url})"
    end

    def section(heading, body)
      stripped = body.to_s.strip
      return nil if stripped.blank?
      "### #{heading}\n\n#{stripped}"
    end
  end
end
