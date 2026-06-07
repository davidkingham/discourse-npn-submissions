# frozen_string_literal: true

module DiscourseNpnSubmissions
  # Builds the Markdown body of the topic created from a Help submission —
  # the "ask for help" form. Kept separate from the critique/project/intro/
  # new-member-image builders because the layout is intentionally minimal:
  # the user's description, any screenshots, and an optional collapsed
  # diagnostic-info block.
  #
  # Field key convention (matches Submission#field):
  #   - `description`     — required free text, becomes the post body
  #                         under "### What's happening"
  #   - `diagnostic_info` — optional pre-formatted Markdown produced by the
  #                         client when the user opts in (browser, OS,
  #                         device + viewport, came-from URL). Wrapped in
  #                         a [details] block so it sits there for
  #                         moderators without dominating the post.
  #
  # The client decides the content of the diagnostic block — if the user
  # unchecks the "Include diagnostic info" toggle, the field is empty and
  # no block is emitted.
  module HelpPostBuilder
    DESCRIPTION_HEADING = "What's happening"
    SCREENSHOTS_HEADING = "Screenshots"
    DIAGNOSTIC_LABEL = "Diagnostic info"

    module_function

    def build(submission)
      parts = []
      parts << section(DESCRIPTION_HEADING, submission.field("description"))
      parts << screenshots_block(submission)
      parts << diagnostic_block(submission)
      parts.reject(&:blank?).join("\n\n").strip
    end

    # All attached screenshots, in submission order. Each image is rendered
    # as a normal Markdown image so Discourse cooks it as usual (lightbox,
    # thumbnails, etc.). A per-image caption (`note`) becomes a small
    # italic line below its image.
    def screenshots_block(submission)
      entries = submission.image_entries
      return nil if entries.empty?

      blocks =
        entries.each_with_index.flat_map do |entry, index|
          alt = "Screenshot #{index + 1}"
          rows = ["![#{alt}](#{entry[:upload].short_url})"]
          rows << "*#{entry[:note]}*" if entry[:note].present?
          rows
        end

      "### #{SCREENSHOTS_HEADING}\n\n#{blocks.join("\n\n")}"
    end

    # The collapsed diagnostic-info block. Only rendered when the client
    # has supplied a non-blank, pre-formatted Markdown body — meaning the
    # user opted in to including it. Cooked inside [details] so it's
    # present-but-quiet in the topic view.
    def diagnostic_block(submission)
      body = submission.field("diagnostic_info").to_s.strip
      return nil if body.blank?

      "[details=\"#{DIAGNOSTIC_LABEL}\"]\n#{body}\n[/details]"
    end

    def section(heading, body)
      stripped = body.to_s.strip
      return nil if stripped.blank?
      "### #{heading}\n\n#{stripped}"
    end
  end
end
