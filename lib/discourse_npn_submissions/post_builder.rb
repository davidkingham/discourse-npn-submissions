# frozen_string_literal: true

module DiscourseNpnSubmissions
  # Builds the Markdown body of the topic created from an Image Critique
  # submission. Kept separate from the Submitter so the post format can be
  # refined without touching submission/authorization logic.
  #
  # Layout: main image, then any additional images (with optional italic notes),
  # then a blockquote header (critique style + feedback focus), then h3 sections
  # that vary by critique style. Initial Reaction hides its later sections in a
  # [spoiler] block so viewers can react before reading the photographer's notes.
  module PostBuilder
    STYLE_LABELS = {
      "standard" => "Standard",
      "in_depth" => "In-Depth",
      "reaction" => "Initial Reaction",
    }.freeze

    # Title-cased to match the form's feedback-focus card titles, so the form and
    # the generated post read consistently.
    FOCUS_LABELS = {
      "artistic" => "Artistic / Expressive",
      "technical" => "Technical Help",
      "both" => "Artistic + Technical",
    }.freeze

    STYLE_DESCRIPTORS = {
      "standard" =>
        "The photographer is looking for thoughtful feedback on the image as a whole, especially around the areas noted below.",
      "in_depth" =>
        "The photographer is looking for deeper feedback connected to their intent, creative direction, and specific questions.",
      "reaction" =>
        "Please share your first response before reading the hidden notes below. The photographer is looking for an unbiased initial impression.",
    }.freeze

    HEADINGS = {
      "about_this_image" => "About This Image",
      "feedback_requested" => "Feedback Requested",
      "technical_details" => "Technical Details",
      "self_critique" => "Self-Critique",
      "creative_direction" => "Creative Direction",
      "questions_for_viewers" => "Questions for Viewers",
      "feedback_after" => "Feedback Requested",
    }.freeze

    module_function

    def build(submission)
      # Projects have their own (isolated) builder; this one handles single-image
      # critiques and weekly challenges.
      return ProjectPostBuilder.build(submission) if submission.project?

      parts = []
      parts.concat(images(submission))
      parts << weekly_challenge_section(submission)
      parts << critique_guidance(submission)
      parts.concat(sections(submission))
      parts.reject(&:blank?).join("\n\n").strip
    end

    # For weekly challenge submissions, identify which challenge the image was
    # submitted for, using the WordPress-synced title (and dates if present), as a
    # subtle contextual callout. Built from the same cached service the panel and
    # preview use, so preview and the final post always match. Omitted entirely
    # when sync is unavailable — the weekly tag and category already mark it as a
    # weekly submission, so we never invent a generic title. The description is
    # intentionally not included (the post identifies the challenge; it doesn't
    # repeat the full prompt). Placed after the images, before the guidance card.
    #
    # Rendered as a scoped raw-HTML block (allowlisted in discourse-markdown so it
    # survives cooking) with no blank lines inside, so the contents pass through
    # as literal HTML; dynamic values are HTML-escaped.
    def weekly_challenge_section(submission)
      return nil unless submission.weekly_challenge?

      info = WeeklyChallengeInfo.current
      return nil if info.blank? || info[:title].blank?

      lines = [
        %(<div class="npn-weekly-challenge-context">),
        "<h3>Weekly Challenge</h3>",
        %(<div class="npn-weekly-challenge-title">#{escape_html(info[:title])}</div>),
      ]
      if info[:dates].present?
        lines << %(<div class="npn-weekly-challenge-dates">#{escape_html(info[:dates])}</div>)
      end
      lines << "</div>"
      lines.join("\n")
    end

    # All images in upload order, before the critique text. The first image is
    # the main image (alt text = title); later images use their note as alt
    # text when present, otherwise "Additional image N". A note, when present,
    # is rendered beneath the image in italics.
    def images(submission)
      submission.image_entries.each_with_index.flat_map do |entry, index|
        chunk = ["![#{image_alt(submission, entry, index)}](#{entry[:upload].short_url})"]
        chunk << "*#{entry[:note]}*" if entry[:note].present?
        chunk
      end
    end

    def image_alt(submission, entry, index)
      return submission.title if index.zero?
      entry[:note].presence || "Additional image #{index}"
    end

    # A quiet, structured guidance card (not a blockquote) telling members how the
    # photographer wants feedback: the critique style, a short explanation of that
    # style, and the feedback focus. Rendered as a scoped raw-HTML block
    # (allowlisted in discourse-markdown) so plugin CSS can style it as subtle
    # contextual guidance. The labels/values come from trusted constants/enums.
    def critique_guidance(submission)
      style = submission.critique_style
      rows = [
        %(<div class="npn-critique-guidance">),
        %(<div class="npn-critique-guidance-row"><strong>Critique Style:</strong> #{STYLE_LABELS[style] || style}</div>),
      ]

      descriptor = STYLE_DESCRIPTORS[style]
      rows << "<p>#{descriptor}</p>" if descriptor.present?

      if submission.feedback_focus.present?
        focus = FOCUS_LABELS[submission.feedback_focus] || submission.feedback_focus
        rows << %(<div class="npn-critique-guidance-row"><strong>Feedback Focus:</strong> #{focus}</div>)
      end

      rows << "</div>"
      rows.join("\n")
    end

    def sections(submission)
      case submission.critique_style
      when "standard"
        standard_sections(submission)
      when "in_depth"
        in_depth_sections(submission)
      when "reaction"
        reaction_sections(submission)
      else
        []
      end
    end

    def standard_sections(submission)
      [
        section("about_this_image", submission.field("about_this_image")),
        section("feedback_requested", submission.field("feedback_requested")),
        technical_section(submission),
      ].compact
    end

    def in_depth_sections(submission)
      [
        section("self_critique", submission.field("self_critique")),
        section("creative_direction", submission.field("creative_direction")),
        section("feedback_requested", submission.field("feedback_requested")),
        section("about_this_image", submission.field("about_this_image")),
        technical_section(submission),
      ].compact
    end

    def reaction_sections(submission)
      parts = []
      visible = section("questions_for_viewers", submission.field("questions_for_viewers"))
      parts << visible if visible

      hidden = [
        section("about_this_image", submission.field("about_this_image")),
        technical_section(submission),
        section("feedback_after", submission.field("feedback_after")),
      ].compact
      parts << ["[spoiler]", *hidden, "[/spoiler]"].join("\n\n") if hidden.any?

      parts
    end

    # Technical Details combines the optional text answer and the optional
    # metadata screenshot under a single heading. Text first, then screenshot.
    # Omitted entirely when neither is present.
    def technical_section(submission)
      text = submission.field("technical_details")
      screenshot = submission.metadata_screenshot_upload
      return nil if text.blank? && screenshot.blank?

      body = []
      body << preserve_line_breaks(text) if text.present?
      body << metadata_screenshot(screenshot) if screenshot
      "### #{HEADINGS["technical_details"]}\n\n#{body.join("\n\n")}"
    end

    # Technical metadata is usually a stack of single lines (Camera / Lens /
    # Focal length / …). Convert lone newlines to Markdown hard breaks so each
    # line renders separately regardless of the forum's traditional-linebreaks
    # setting; paragraph breaks (blank lines) are left intact.
    def preserve_line_breaks(text)
      text.gsub(/(?<!\n)\n(?!\n)/, "  \n")
    end

    # A metadata screenshot is supporting technical context, not part of the
    # photographic work, so it's wrapped in a scoped class the plugin CSS renders
    # smaller and secondary. The blank lines keep the Markdown image parseable
    # (so its upload:// short URL still resolves) inside the raw <div>.
    def metadata_screenshot(upload)
      [
        %(<div class="npn-metadata-screenshot">),
        "",
        "![Metadata screenshot](#{upload.short_url})",
        "",
        "</div>",
      ].join("\n")
    end

    def section(key, body)
      return nil if body.blank?
      "### #{HEADINGS[key] || key}\n\n#{body}"
    end

    # Escape dynamic (WordPress-synced) text before embedding it in a raw-HTML
    # callout, so a stray & or < can't break the markup. The values are already
    # plain text from WeeklyChallengeInfo; this is defence in depth.
    def escape_html(text)
      CGI.escapeHTML(text.to_s)
    end
  end
end
