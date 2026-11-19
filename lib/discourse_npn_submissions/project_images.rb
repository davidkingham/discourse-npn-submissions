# frozen_string_literal: true

module DiscourseNpnSubmissions
  # The numbered "building blocks" of an image-method project, serialized on
  # topic view as `npn_project_images` so the client can show the project strip
  # in the reply composer and drive the Suggest-a-Sequence builder.
  #
  # Numbering contract: an original image's `number` is its ORIGINAL submission
  # position ("1", "2", …) and alternates are "A1", "A2", …. Sequence blocks in
  # replies label tiles with these numbers, so they must never be renumbered —
  # a future revision tool should keep numbers attached to slots, not to
  # whatever happens to sit at that position now.
  module ProjectImages
    module_function

    # Returns { originals: [...], alternates: [...] } or nil when the
    # submission isn't an image-method project (PDF/URL projects have no tiles)
    # or has no surviving images.
    def build(submission, topic: nil)
      return nil unless submission&.project?
      return nil unless submission.project_method == "images"

      entries = Array(submission.image_entries)
      return nil if entries.empty?

      slot_ids = slot_ids_for(topic)

      originals =
        entries.each_with_index.map do |entry, index|
          image_hash(entry, (index + 1).to_s, slot_id: slot_ids[index + 1])
        end

      alternates =
        Array(submission.alternate_entries).each_with_index.map do |entry, index|
          image_hash(entry, "A#{index + 1}")
        end

      { originals: originals, alternates: alternates }
    end

    def image_hash(entry, number, slot_id: nil)
      upload = entry[:upload]
      width, height = display_dimensions(upload)
      {
        number: number,
        slot_id: slot_id,
        upload_id: upload.id,
        short_url: upload.short_url,
        url: UrlHelper.cook_url(upload.url, secure: upload.secure?),
        sheet_url: sheet_url(upload, width, height),
        width: width,
        height: height,
        caption: entry[:note].presence,
      }
    end

    # The size Discourse itself would put in `![alt|WxH](…)` for this upload:
    # the thumbnail box (fits max_image_width/height), falling back to the
    # original size. Only the ratio really matters — sequence CSS fixes the
    # tile height — but realistic numbers keep the optimized image small.
    def display_dimensions(upload)
      width = upload.thumbnail_width.presence || upload.width
      height = upload.thumbnail_height.presence || upload.height
      return nil, nil if width.to_i <= 0 || height.to_i <= 0
      [width.to_i, height.to_i]
    end

    # A mid-size rendition for drawing the suggested-sequence contact sheet in
    # the browser, so it doesn't download full-size originals: the optimized
    # image Discourse already made for the post at the display size. nil when
    # none exists (the client falls back to the original).
    def sheet_url(upload, width, height)
      return nil if width.nil? || height.nil?
      optimized = upload.optimized_images.find { |o| o.width == width && o.height == height }
      optimized && UrlHelper.cook_url(optimized.url, secure: upload.secure?)
    rescue StandardError
      nil
    end

    # Stable slot ids from the structured project payload, keyed by position.
    def slot_ids_for(topic)
      data = topic&.custom_fields&.[](TopicMetadata::PROJECT_SUBMISSION_DATA_KEY)
      data = JSON.parse(data) if data.is_a?(String)
      return {} unless data.is_a?(Hash)

      Array(data["images"]).each_with_object({}) do |image, out|
        next unless image.is_a?(Hash)
        position = image["position"].to_i
        out[position] = image["id"].to_s.presence if position.positive?
      end
    rescue JSON::ParserError
      {}
    end
  end
end
