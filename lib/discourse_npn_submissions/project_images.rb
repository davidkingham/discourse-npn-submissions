# frozen_string_literal: true

module DiscourseNpnSubmissions
  # The numbered "building blocks" of an image-method project, serialized on
  # topic view as `npn_project_images` so the client can show the project strip
  # in the reply composer and drive the Suggest-a-Sequence builder.
  #
  # Numbering: an image's `number` is its position in the project AS THE POST
  # SHOWS IT NOW ("1", "2", …) and alternates are "A1", "A2", …. Without a
  # revision that's the submission order. Once the photographer posts a
  # project revision (discourse-npn-revised-critique), `originals` follow the
  # latest revision — its order and any replaced images — so the numbers on
  # the wall, the sequence builder and the suggested-edit tags match the
  # "Image N" labels readers see. `slot_id` stays attached to the image across
  # revisions for anything that needs a stable identity.
  module ProjectImages
    # Written by discourse-npn-revised-critique; read here without depending
    # on that plugin being loaded.
    PROJECT_REVISIONS_KEY = "npn_project_revisions"

    module_function

    # Returns { originals: [...], alternates: [...] } or nil when the
    # submission isn't an image-method project (PDF/URL projects have no tiles)
    # or has no surviving images.
    def build(submission, topic: nil)
      return nil unless submission&.project?
      return nil unless submission.project_method == "images"

      entries = Array(submission.image_entries)
      return nil if entries.empty?

      revision = latest_revision(topic)
      revised = revision && revised_entries(revision)

      originals =
        if revised.present?
          revised.each_with_index.map do |(entry, slot_id), index|
            image_hash(entry, (index + 1).to_s, slot_id: slot_id)
          end
        else
          slot_ids = slot_ids_for(topic)
          entries.each_with_index.map do |entry, index|
            image_hash(entry, (index + 1).to_s, slot_id: slot_ids[index + 1])
          end
        end

      alternates =
        Array(submission.alternate_entries).each_with_index.map do |entry, index|
          image_hash(entry, "A#{index + 1}")
        end

      {
        originals: originals,
        alternates: alternates,
        feedback_types: submission.project_feedback_types,
        intent: submission.field("project_intent").presence,
        revision: revised.present? ? revision["revision_number"].to_i : nil,
        hang: revision_hang(revision, revised) || submission.project_hang,
      }
    end

    # A revision carries its own hang (layout, look, sizes for its prints);
    # nil when it has none, so the submission's hang applies.
    def revision_hang(revision, revised)
      return nil if revised.blank?
      raw = revision["hang"]
      raw.is_a?(Hash) ? ProjectHang.normalize(raw) : nil
    end

    # The latest project revision entry, or nil.
    def latest_revision(topic)
      raw = topic&.custom_fields&.[](PROJECT_REVISIONS_KEY)
      raw = JSON.parse(raw) if raw.is_a?(String)
      latest = Array(raw).last
      latest.is_a?(Hash) ? latest : nil
    rescue JSON::ParserError
      nil
    end

    # [[{ upload:, note: }, slot_id], …] in the revision's order. Images whose
    # upload no longer exists are skipped; nil when nothing survives.
    def revised_entries(revision)
      images =
        Array(revision["images"])
          .select { |image| image.is_a?(Hash) && image["upload_id"].to_i.positive? }
          .sort_by { |image| image["position"].to_i }
      uploads = Upload.where(id: images.map { |i| i["upload_id"].to_i }).index_by(&:id)
      entries =
        images.filter_map do |image|
          upload = uploads[image["upload_id"].to_i]
          next if upload.nil?
          [{ upload: upload, note: image["caption"].to_s }, image["id"].to_s.presence]
        end
      entries.presence
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
        original_width: upload.width,
        original_height: upload.height,
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
