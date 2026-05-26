# frozen_string_literal: true

module DiscourseNpnSubmissions
  class Submission < ::ActiveRecord::Base
    self.table_name = "npn_submissions"

    SUBMISSION_TYPES = %w[image project weekly_challenge].freeze
    CRITIQUE_STYLES = %w[standard in_depth reaction].freeze
    FEEDBACK_FOCUSES = %w[artistic technical both].freeze
    STATUSES = %w[draft submitted failed].freeze

    # Types that require at least one image, a critique style and a feedback focus.
    UPLOAD_REQUIRED_TYPES = %w[image weekly_challenge].freeze
    CRITIQUE_STYLE_REQUIRED_TYPES = %w[image weekly_challenge].freeze

    # Types that require at least one user-selected descriptive tag.
    TAG_REQUIRED_TYPES = %w[image weekly_challenge project].freeze

    # Per-style fields that must be filled in before submitting. Technical Details
    # is required separately when feedback_focus is "technical".
    REQUIRED_FIELDS_BY_STYLE = {
      "standard" => %w[feedback_requested],
      "in_depth" => %w[self_critique creative_direction feedback_requested],
      "reaction" => %w[questions_for_viewers],
    }.freeze

    # Project submissions. The work is a body of images, a PDF, or an external
    # link, with a fixed set of reflective questions (no critique style).
    PROJECT_METHODS = %w[images pdf url].freeze
    PROJECT_REQUIRED_FIELDS = %w[
      project_description
      self_critique
      creative_direction
      feedback_requested
      project_intent
    ].freeze
    PROJECT_INTENTS = %w[gallery lwfull lwis on magazine web book fun other].freeze

    belongs_to :user
    belongs_to :topic, optional: true

    has_many :submission_uploads,
             class_name: "DiscourseNpnSubmissions::SubmissionUpload",
             foreign_key: :submission_id,
             dependent: :destroy
    has_many :uploads, through: :submission_uploads

    validates :submission_type, presence: true, inclusion: { in: SUBMISSION_TYPES }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :critique_style, inclusion: { in: CRITIQUE_STYLES }, allow_nil: true

    scope :drafts, -> { where(status: "draft") }
    scope :submitted, -> { where(status: "submitted") }
    scope :failed, -> { where(status: "failed") }
    scope :for_user, ->(user) { where(user_id: user.id) }

    # --- Accessors over the `data` JSON. Single source of truth for parsing the
    # submission payload, used by the validator, post builder and persistence. ---

    def weekly_challenge?
      submission_type == "weekly_challenge"
    end

    def project?
      submission_type == "project"
    end

    # "images" | "pdf" | "url" for project submissions.
    def project_method
      data["method"].to_s.strip
    end

    def feedback_focus
      data["feedback_focus"].to_s.strip
    end

    # A per-style answer by canonical key (see REQUIRED_FIELDS_BY_STYLE and
    # PostBuilder::HEADINGS). Always returns a stripped string.
    def field(key)
      data.dig("fields", key.to_s).to_s.strip
    end

    # Canonical, ordered list of images: [{ upload: Upload, note: String }].
    # The first entry is the "main" image; the rest are additional images /
    # variations. Only uploads that still exist are returned, and a given upload
    # appears at most once (the same file can't be listed twice).
    def image_entries
      @image_entries ||= entries_from(image_data)
    end

    def main_upload
      image_entries.first&.fetch(:upload)
    end

    # [{ upload: Upload, note: String }] for every image after the first.
    def additional_image_entries
      image_entries.drop(1)
    end

    # Optional metadata/EXIF screenshot tied to Technical Details. Stored as a
    # single upload id alongside the critique images, never counted as a
    # critique image itself.
    def metadata_screenshot_upload
      id = data["metadata_screenshot_upload_id"].to_i
      id.zero? ? nil : Upload.find_by(id: id)
    end

    # Optional alternate project images: [{ upload:, note: }]. Never count toward
    # the main project image recommendation. An upload already listed as a project
    # image is dropped here, so the same file is never shown (or persisted) twice.
    def alternate_entries
      @alternate_entries ||=
        entries_from(data["alternates"], exclude_ids: image_entries.map { |e| e[:upload].id })
    end

    # The single uploaded PDF for a PDF-method project, if any.
    def pdf_upload
      id = data["pdf_upload_id"].to_i
      id.zero? ? nil : Upload.find_by(id: id)
    end

    # The image that represents a PDF/URL project in topic lists (so the post
    # has a thumbnail). Not used for uploaded-image projects.
    def representative_image_upload
      id = data["representative_image_upload_id"].to_i
      id.zero? ? nil : Upload.find_by(id: id)
    end

    def project_link
      data["link_url"].to_s.strip
    end

    def project_link_description
      data["link_description"].to_s.strip
    end

    # Every referenced upload (critique/project images plus the optional metadata
    # screenshot, project alternates and PDF), used for ownership checks.
    def referenced_uploads
      [
        *image_entries.map { |entry| entry[:upload] },
        *alternate_entries.map { |entry| entry[:upload] },
        metadata_screenshot_upload,
        pdf_upload,
        representative_image_upload,
      ].compact
    end

    def descriptive_tag_names
      Array(data["tags"]).map(&:to_s).map(&:strip).reject(&:blank?).uniq
    end

    private

    # Build [{ upload:, note: }] from a raw entries array, dropping non-hashes,
    # missing uploads, any upload id in `exclude_ids`, and repeats of an upload
    # already seen — so a given file is listed at most once.
    def entries_from(raw, exclude_ids: [])
      seen = exclude_ids.compact.map(&:to_i)
      Array(raw).filter_map do |entry|
        next unless entry.is_a?(Hash)
        upload = Upload.find_by(id: entry["upload_id"].to_i)
        next unless upload
        next if seen.include?(upload.id)
        seen << upload.id
        { upload: upload, note: entry["note"].to_s.strip }
      end
    end

    # Prefer the unified `images` array. Fall back to the pre-unified shape
    # (main_upload_id + additional_images) so older drafts still render.
    def image_data
      return data["images"] if data["images"].present?

      legacy = []
      main_id = data["main_upload_id"]
      legacy << { "upload_id" => main_id, "note" => "" } if main_id.present?
      Array(data["additional_images"]).each { |e| legacy << e if e.is_a?(Hash) }
      legacy
    end
  end
end

# == Schema (informational)
#
# Table name: npn_submissions
#
#  id              :bigint
#  user_id         :integer  not null
#  submission_type :string   not null   # image | project | weekly_challenge
#  critique_style  :string              # standard | in_depth | reaction | nil
#  status          :string   not null   # draft | submitted | failed
#  title           :string
#  data            :jsonb    not null
#  topic_id        :integer
#  error_message   :text
#  client_timezone :string
#  submitted_at    :datetime
#  created_at      :datetime not null
#  updated_at      :datetime not null
