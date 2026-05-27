# frozen_string_literal: true

module DiscourseNpnSubmissions
  # Builds the Markdown body of the topic created from a Project Critique
  # submission. Kept separate from the image/weekly PostBuilder because a project
  # is a body of work (images / PDF / link) with a fixed set of reflective
  # questions rather than a single critique image.
  #
  # Layout (all headings h3): the project media first, then Project Description,
  # Creative Direction, Self-Critique, Feedback Requested, Presentation Goal,
  # and an optional Alternate Images section. Blank optional sections are omitted.
  # Uploaded images are posted in order as normal images.
  module ProjectPostBuilder
    HEADINGS = {
      "project_description" => "Brief Project Description",
      "self_critique" => "Self-Critique",
      "creative_direction" => "Creative Direction",
      "feedback_requested" => "Feedback Requested",
    }.freeze

    INTENT_LABELS = {
      "gallery" => "Gallery Exhibition",
      "lwfull" => "LensWork Full-Project Submission",
      "lwis" => "LensWork Image Suite Submission",
      "on" => "On Landscape Submission",
      "magazine" => "Magazine Submission",
      "web" => "Gallery on your website",
      "book" => "Book Publication",
      "fun" => "Just for fun",
      "other" => "Other",
    }.freeze

    module_function

    def build(submission)
      parts = []
      parts << media_section(submission)
      # Reflective narrative order: what the project is, the creative
      # direction, what is/isn't working, what feedback is wanted.
      parts << section("project_description", submission.field("project_description"))
      parts << section("creative_direction", submission.field("creative_direction"))
      parts << section("self_critique", submission.field("self_critique"))
      parts << section("feedback_requested", submission.field("feedback_requested"))
      parts << intent_section(submission)
      parts << alternates_section(submission)
      parts.reject(&:blank?).join("\n\n").strip
    end

    def media_section(submission)
      case submission.project_method
      when "images"
        images_section(submission)
      when "pdf"
        pdf_card(submission)
      when "url"
        url_card(submission)
      end
    end

    # Uploaded-image projects get two complementary views, in submission order:
    # a numbered contact-sheet "Project Overview" grid for at-a-glance scanning,
    # then "Image Sequence" with the full images (and any captions).
    def images_section(submission)
      entries = submission.image_entries
      return nil if entries.empty?

      [overview_grid(entries), image_sequence(entries)].join("\n\n")
    end

    # A quiet contact-sheet overview: every image shown small but UNCROPPED (the
    # CSS uses object-fit: contain), in order, with the number as a label BELOW
    # the image so it never covers the photograph. Raw HTML so plugin CSS can lay
    # it out as an even grid; the classes are allowlisted in
    # assets/javascripts/lib/discourse-markdown so they survive cooking. Real
    # upload URLs are used (Discourse still tracks the upload from the /uploads/
    # src). Must be one contiguous HTML block — no blank lines inside.
    def overview_grid(entries)
      cells =
        entries.each_with_index.flat_map do |entry, index|
          label = "Image #{index + 1}"
          [
            '<div class="npn-project-overview-item">',
            # Label in its own row ABOVE the image so it sits at a consistent
            # position regardless of image height, and never covers the photo.
            %(<div class="npn-project-overview-label">#{label}</div>),
            '<div class="npn-project-overview-frame">',
            %(<img class="npn-project-overview-image" src="#{h(entry[:upload].url)}" alt="#{label}" loading="lazy">),
            "</div>",
            "</div>",
          ]
        end

      [
        "### Project Overview",
        "",
        '<div class="npn-project-overview-grid">',
        *cells,
        "</div>",
      ].join("\n")
    end

    # The full images below the overview, in order. Each is preceded by a bold
    # "Image N" label (matching the overview) and followed by its optional
    # caption/note. Markdown images so Discourse optimizes them and wires its
    # lightbox as usual; blank lines keep each image a proper block image.
    def image_sequence(entries)
      blocks =
        entries.each_with_index.flat_map do |entry, index|
          parts = ["**Image #{index + 1}**", "![Image #{index + 1}](#{entry[:upload].short_url})"]
          parts << "*#{entry[:note]}*" if entry[:note].present?
          parts
        end

      "### Image Sequence\n\n#{blocks.join("\n\n")}"
    end

    # A compact "access card" where the PDF/link is the hero and the
    # representative image is a supporting thumbnail (it also seeds the topic
    # thumbnail). Raw HTML so it can be laid out and styled; the classes are
    # allowlisted in assets/javascripts/lib/discourse-markdown so they survive
    # cooking. Real upload URLs are used (no upload:// in raw HTML) — Discourse
    # still tracks the upload and builds the thumbnail from the /uploads/ src.
    # Must be a single contiguous HTML block (no blank lines inside).
    def url_card(submission)
      url = submission.project_link
      return nil if url.blank?

      lines = ['<div class="npn-project-access-card">']
      lines << card_thumb(submission, url)
      lines << '<div class="npn-project-access-content">'
      lines << '<span class="npn-project-access-label">Project Link</span>'
      # Show the destination (the domain) rather than re-linking the project
      # title — the title is already the topic title, and the CTA is the link.
      host = link_host(url)
      lines << %(<div class="npn-project-access-title">#{h(host)}</div>) if host.present?
      description = submission.project_link_description
      lines << %(<div class="npn-project-access-desc">#{h(description)}</div>) if description.present?
      lines << %(<a class="npn-project-access-button" href="#{h(url)}">View Project →</a>)
      lines << "</div>"
      lines << "</div>"
      lines.compact.join("\n")
    end

    def link_host(url)
      URI.parse(url).host&.delete_prefix("www.")
    rescue URI::InvalidURIError
      nil
    end

    def pdf_card(submission)
      pdf = submission.pdf_upload
      return nil unless pdf

      size = ActiveSupport::NumberHelper.number_to_human_size(pdf.filesize)
      lines = ['<div class="npn-project-access-card">']
      lines << card_thumb(submission, pdf.url)
      lines << '<div class="npn-project-access-content">'
      lines << '<span class="npn-project-access-label">Project PDF</span>'
      lines << %(<div class="npn-project-access-title">#{h(pdf.original_filename)} (#{size})</div>)
      lines << %(<a class="npn-project-access-button" href="#{h(pdf.url)}">Open PDF →</a>)
      lines << "</div>"
      lines << "</div>"
      lines.compact.join("\n")
    end

    # The supporting thumbnail, linked to the project. Nil (skipped) if there is
    # no representative image, though validation requires one for PDF/URL.
    def card_thumb(submission, href)
      upload = submission.representative_image_upload
      return nil unless upload

      %(<a class="npn-project-access-thumb" href="#{h(href)}"><img src="#{h(upload.url)}" alt="#{h(submission.title)}"></a>)
    end

    def h(text)
      CGI.escapeHTML(text.to_s)
    end

    # The "Presentation Goal" section describes how/where the photographer
    # intends to present the project (LensWork submission, magazine, website,
    # print, just for fun, etc.) — separate from creative direction. The
    # optional Additional Details note is appended as a bold-labelled line so
    # it's clearly subordinate to the goal itself.
    def intent_section(submission)
      intent = submission.field("project_intent")
      return nil if intent.blank?

      body = [INTENT_LABELS[intent] || intent]
      details = submission.field("project_intent_details")
      body << "**Additional Details:** #{details}" if details.present?
      "### Presentation Goal\n\n#{body.join("\n\n")}"
    end

    def alternates_section(submission)
      entries = submission.alternate_entries
      return nil if entries.empty?

      images =
        entries.each_with_index.map do |entry, index|
          "![Alternate #{index + 1}](#{entry[:upload].short_url})"
        end

      [
        "### Alternate Images",
        "Please provide feedback on whether any of these images would fit more cohesively in the project.",
        *images,
      ].join("\n\n")
    end

    def section(key, body)
      return nil if body.blank?
      "### #{HEADINGS[key] || key}\n\n#{body}"
    end
  end
end
