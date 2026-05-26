# frozen_string_literal: true

module DiscourseNpnSubmissions
  class SubmissionSerializer < ::ApplicationSerializer
    attributes :id,
               :submission_type,
               :critique_style,
               :status,
               :title,
               :data,
               :images,
               :alternates,
               :pdf,
               :representative_image,
               :metadata_screenshot,
               :topic_id,
               :topic_url,
               :error_message,
               :client_timezone,
               :created_at,
               :updated_at,
               :submitted_at

    def topic_url
      "/t/#{object.topic_id}"
    end

    def include_topic_url?
      object.topic_id.present?
    end

    # Hydrated uploads so a draft can be reloaded into the form with its
    # thumbnails intact — the raw `data.images` only stores upload ids/notes.
    def images
      object.image_entries.map do |entry|
        upload = entry[:upload]
        {
          id: upload.id,
          url: upload.url,
          original_filename: upload.original_filename,
          note: entry[:note],
        }
      end
    end

    def metadata_screenshot
      upload = object.metadata_screenshot_upload
      return nil unless upload

      {
        id: upload.id,
        url: upload.url,
        original_filename: upload.original_filename,
      }
    end

    # Hydrated project alternates and PDF, so a project draft can be reloaded
    # into the form. Empty / nil for non-project submissions.
    def alternates
      object.alternate_entries.map do |entry|
        upload = entry[:upload]
        {
          id: upload.id,
          url: upload.url,
          original_filename: upload.original_filename,
          note: entry[:note],
        }
      end
    end

    def pdf
      upload = object.pdf_upload
      return nil unless upload

      {
        id: upload.id,
        url: upload.url,
        original_filename: upload.original_filename,
        human_filesize: ActiveSupport::NumberHelper.number_to_human_size(upload.filesize),
      }
    end

    def representative_image
      upload = object.representative_image_upload
      return nil unless upload

      {
        id: upload.id,
        url: upload.url,
        original_filename: upload.original_filename,
      }
    end
  end
end
