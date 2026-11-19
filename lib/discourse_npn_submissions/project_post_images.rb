# frozen_string_literal: true

module DiscourseNpnSubmissions
  # Fallback source of a project's numbered images for project topics that
  # have NO submission row (posted before the current project form, imported,
  # or hand-written): read them from the first post's raw Markdown.
  #
  # Live project posts come in several shapes, so this is deliberately
  # section-aware rather than "every image in the post":
  #
  # - Current form output: `### Image Sequence` (inside the
  #   npn-project-submission markers). The `### Project Overview` grid is raw
  #   HTML (not Markdown images), so it's ignored naturally.
  # - "(+revised)" posts: a second full set lives inside
  #   `[details="Original Submission"]`; revision blocks
  #   (`<!-- revised-critique-image:begin/end -->`) hold single replacement
  #   images. Both are stripped before looking for the sequence.
  # - Older masonry form: every image appears twice — a `data-masonry-gallery`
  #   block and an `Individual Images` list — linked by full https URL rather
  #   than upload://. The Individual Images list is used.
  # - "Cover + images appended" posts: one image before the first heading
  #   (a representative/cover image), the project images after. The cover is
  #   skipped when there are images after it.
  #
  # Alternates are taken from an `Alternate Images` section in any format.
  # Images are matched to uploads by short URL (upload://) or by the 40-hex
  # sha1 in a full upload URL. Fewer than MIN_IMAGES originals → nil (not
  # enough to treat as a project; no tools shown).
  module ProjectPostImages
    MIN_IMAGES = 2

    IMAGE_REGEXP = /!\[([^\]]*)\]\(([^)\s]+)[^)]*\)/
    HEADING_REGEXP = /^\s*\#{1,6}\s+(.+?)\s*$/
    # Bold pseudo-headings the older form used ("**Individual Images**").
    # Only these known titles count: bold per-image labels ("**Image 3**",
    # "**Alternate Image 2**") sit next to every image and are NOT sections.
    BOLD_HEADING_REGEXP =
      /^\s*\*\*\s*(gallery overview|individual images|alternate images?)\s*\*\*\s*$/i
    SHA1_REGEXP = /([0-9a-f]{40})/

    # The project form's "Presentation Goal" labels → intent keys, so older
    # posts pick the same exhibition style as form submissions.
    INTENT_LABELS = {
      "gallery exhibition" => "gallery",
      "lenswork full-project submission" => "lwfull",
      "lenswork image suite submission" => "lwis",
      "on landscape submission" => "on",
      "magazine submission" => "magazine",
      "gallery on your website" => "web",
      "book publication" => "book",
      "just for fun" => "fun",
      "other" => "other",
    }.freeze

    module_function

    # => { originals: [...], alternates: [...] } (ProjectImages hash shape,
    #    plus source: "post") or nil.
    def build(topic)
      post = topic&.first_post
      raw = post&.raw.to_s
      return nil if raw.blank?

      body = strip_extras(raw)
      original_refs, alternate_refs = extract_refs(body)
      return nil if original_refs.size < MIN_IMAGES

      uploads = resolve_uploads(original_refs + alternate_refs)
      originals = to_entries(original_refs, uploads)
      return nil if originals.size < MIN_IMAGES
      alternate_ids = originals.map { |e| e[:upload].id }
      alternates =
        to_entries(alternate_refs, uploads).reject { |e| alternate_ids.include?(e[:upload].id) }

      {
        originals:
          originals.each_with_index.map do |entry, index|
            ProjectImages.image_hash(entry, (index + 1).to_s)
          end,
        alternates:
          alternates.each_with_index.map do |entry, index|
            ProjectImages.image_hash(entry, "A#{index + 1}")
          end,
        feedback_types: [],
        intent: intent_from(body),
        revision: nil,
        source: "post",
      }
    rescue StandardError => e
      Discourse.warn_exception(
        e,
        message:
          "[discourse-npn-submissions] failed to read project images from post for topic=#{topic&.id}",
      )
      nil
    end

    # Drop the parts that hold OTHER copies of images: the original set of a
    # revised post, revision blocks, quotes, and the masonry gallery block.
    def strip_extras(raw)
      raw
        .gsub(%r{\[details[^\]]*\].*?\[/details\]}im, "")
        .gsub(
          /<!--\s*revised-critique-image:begin\s*-->.*?<!--\s*revised-critique-image:end\s*-->/m,
          "",
        )
        .gsub(%r{\[quote[^\]]*\].*?\[/quote\]}im, "")
        .gsub(%r{<div[^>]*data-masonry-gallery[^>]*>.*?</div>}im, "")
    end

    # Splits the body into sections by heading (Markdown or bold line) and
    # picks the project images. Returns [original_refs, alternate_refs],
    # each an ordered list of image URLs.
    def extract_refs(body)
      sections = split_sections(body)

      alternates =
        sections
          .select { |s| s[:title].to_s.match?(/alternate/i) }
          .flat_map { |s| images_in(s[:text]) }
      non_alternate = sections.reject { |s| s[:title].to_s.match?(/alternate/i) }

      sequence =
        non_alternate.find { |s| s[:title].to_s.match?(/\A(image sequence|individual images)\z/i) }
      originals =
        if sequence
          images_in(sequence[:text])
        else
          # No labelled section: every image outside the alternates, minus a
          # leading cover image (before the first heading) when there are
          # images after it.
          lead = non_alternate.first
          lead_images = lead && lead[:title].nil? ? images_in(lead[:text]) : []
          rest = non_alternate.drop(lead_images.any? ? 1 : 0).flat_map { |s| images_in(s[:text]) }
          rest.size >= MIN_IMAGES ? rest : lead_images + rest
        end

      # Anything labelled "Alternate N" in the main list is an alternate too.
      moved, originals = originals.partition { |ref| ref[:alt].match?(/\Aalternate\b/i) }
      [originals.map { |r| r[:url] }.uniq, (alternates + moved).map { |r| r[:url] }.uniq]
    end

    # The first line of a "Presentation Goal" section, matched to a known
    # goal ("Gallery Exhibition" → "gallery"). nil when absent or unknown.
    def intent_from(body)
      section = split_sections(body).find { |s| s[:title].to_s.match?(/\Apresentation goal\z/i) }
      line = section && section[:text].lines.map(&:strip).find(&:present?)
      return nil if line.blank?
      label = line.gsub(/[*_`]/, "").strip.downcase
      INTENT_LABELS[label] || INTENT_LABELS.find { |text, _| label.start_with?(text) }&.last
    end

    def split_sections(body)
      sections = [{ title: nil, text: +"" }]
      body.each_line do |line|
        heading = line[HEADING_REGEXP, 1] || line[BOLD_HEADING_REGEXP, 1]
        if heading && !line.match?(IMAGE_REGEXP)
          sections << { title: heading.strip, text: +"" }
        else
          sections.last[:text] << line
        end
      end
      sections
    end

    def images_in(text)
      text
        .to_s
        .scan(IMAGE_REGEXP)
        .map { |alt, url| { alt: alt.to_s.split("|").first.to_s.strip, url: url } }
    end

    # One batch lookup for every referenced image: upload:// short URLs by
    # their sha1, full URLs by the sha1 in the path.
    def resolve_uploads(urls)
      sha_by_url =
        urls
          .uniq
          .each_with_object({}) do |url, out|
            sha =
              if url.start_with?("upload://")
                Upload.sha1_from_short_url(url)
              else
                url[SHA1_REGEXP, 1]
              end
            out[url] = sha if sha.present?
          end
      by_sha = Upload.where(sha1: sha_by_url.values.uniq).index_by(&:sha1)
      sha_by_url.transform_values { |sha| by_sha[sha] }.compact
    end

    def to_entries(refs, uploads)
      seen = []
      refs.filter_map do |url|
        upload = uploads[url]
        next if upload.nil? || seen.include?(upload.id)
        seen << upload.id
        { upload: upload, note: "" }
      end
    end
  end
end
