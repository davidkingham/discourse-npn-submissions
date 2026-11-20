# frozen_string_literal: true

module DiscourseNpnSubmissions
  class Submission < ::ActiveRecord::Base
    self.table_name = "npn_submissions"

    SUBMISSION_TYPES = %w[image project weekly_challenge introduction new_member_image help].freeze
    CRITIQUE_STYLES = %w[standard in_depth reaction].freeze
    FEEDBACK_FOCUSES = %w[artistic technical both].freeze
    STATUSES = %w[draft submitted failed].freeze

    # The three critique-bearing types. Used by DailyLimit (introductions don't
    # count against the critique limit) and by anywhere else that needs to ask
    # "is this a critique?" without enumerating types inline.
    CRITIQUE_SUBMISSION_TYPES = %w[image weekly_challenge project].freeze

    # Types whose primary submission image is exposed on the "image-version"
    # surface — the npn_original_* custom fields that discourse-npn-critique-reply
    # reads to load its annotation canvas. The three critique types PLUS New
    # Members Area images: a new-member image isn't a full critique (it stays out
    # of the daily limit and the critique-style flow) but it IS annotated in the
    # critique workspace, so it needs the original-image references. Introduction
    # and help have no annotatable image and stay off this surface.
    IMAGE_VERSION_TYPES = %w[image weekly_challenge project new_member_image].freeze

    # Types that require at least one image, a critique style and a feedback focus.
    UPLOAD_REQUIRED_TYPES = %w[image weekly_challenge].freeze
    CRITIQUE_STYLE_REQUIRED_TYPES = %w[image weekly_challenge].freeze

    # Types that require at least one user-selected descriptive tag.
    # Introduction is deliberately absent — no tags are required (or invited)
    # when introducing yourself.
    TAG_REQUIRED_TYPES = %w[image weekly_challenge project].freeze

    # Critique types whose form lets the photographer opt out of receiving
    # processing examples from other members (a critic downloading the image,
    # making a processing example, and uploading it in their reply). Project
    # critiques are intentionally excluded for now — see TopicMetadata and the
    # form component. Onboarding types never offer the choice. A submission of
    # any other type — or any older topic predating the field — is treated as
    # "allowed" downstream, so we only store the preference for these types.
    PROCESSING_EXAMPLE_OPT_OUT_TYPES = %w[image weekly_challenge].freeze

    # Per-style fields that must be filled in before submitting. Technical Details
    # is required separately when feedback_focus is "technical".
    #
    # In-Depth was simplified to only require the final ask — every earlier
    # field (about the image, why this image, what you're trying to express)
    # is an optional invitation. Beta-era drafts that still carry
    # `self_critique` / `creative_direction` data are surfaced via the
    # renamed "Express or Explore" field on the form, or just left in the
    # JSON without being posted.
    REQUIRED_FIELDS_BY_STYLE = {
      "standard" => %w[feedback_requested],
      "in_depth" => %w[feedback_requested],
      "reaction" => %w[questions_for_viewers],
    }.freeze

    # Project submissions. The work is a body of images, a PDF, or an external
    # link, with a fixed set of reflective questions (no critique style).
    PROJECT_METHODS = %w[images pdf url].freeze
    # "self_critique" was merged into "feedback_requested" (Questions for
    # critics); older submissions may still carry it and the post shows it.
    PROJECT_REQUIRED_FIELDS = %w[
      project_description
      creative_direction
      feedback_requested
      project_intent
    ].freeze
    PROJECT_INTENTS = %w[gallery lwfull lwis on magazine web book fun other].freeze
    # Optional: the kinds of project feedback the photographer wants. Order is
    # the canonical display order.
    # These replaced the project's artistic / technical / both focus question;
    # the focus is now derived from them (see #feedback_focus).
    PROJECT_FEEDBACK_TYPES = %w[cohesion sequence edit individual presentation technical].freeze

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

    # The Weekly Challenge a submitted post was published under, read back from
    # the topic's custom fields when the post is edited through the form. Never
    # persisted. nil means "not set: use the live challenge" (new submissions);
    # an empty Hash means "the post had no challenge section", so an edit never
    # adds one or swaps in the current week's challenge.
    attr_accessor :weekly_challenge_snapshot

    # image_entries / alternate_entries are memoized from `data`; reassigning
    # the payload (the edit-with-form path) must drop those caches.
    def data=(value)
      @image_entries = nil
      @alternate_entries = nil
      super
    end

    # --- Accessors over the `data` JSON. Single source of truth for parsing the
    # submission payload, used by the validator, post builder and persistence. ---

    def weekly_challenge?
      submission_type == "weekly_challenge"
    end

    def project?
      submission_type == "project"
    end

    def introduction?
      submission_type == "introduction"
    end

    def new_member_image?
      submission_type == "new_member_image"
    end

    def help?
      submission_type == "help"
    end

    # "images" | "pdf" | "url" for project submissions.
    def project_method
      data["method"].to_s.strip
    end

    # Projects no longer ask for a focus: it's derived from the requested
    # feedback types (technical only → "technical", technical plus anything
    # else → "both", otherwise "artistic"). A focus saved by the older form
    # still wins.
    def feedback_focus
      value = data["feedback_focus"].to_s.strip
      return value if value.present? || !project?

      types = project_feedback_types
      return "artistic" if types.exclude?("technical")
      types.size > 1 ? "both" : "technical"
    end

    # Requested project feedback types, filtered to the known enum and put in
    # canonical order (unknown values are dropped, never stored onward).
    def project_feedback_types
      requested = Array(data["feedback_types"]).map { |t| t.to_s.strip }
      PROJECT_FEEDBACK_TYPES.select { |t| requested.include?(t) }
    end

    # Whether other members may post processing examples (a downloaded, edited
    # version of the image) as part of their critique. Defaults to true: a
    # missing value means the photographer never touched the control or the
    # draft predates the field, and the product decision is "allowed by
    # default". Downstream readers must treat missing as allowed, too.
    def processing_examples_allowed?
      raw = data["processing_examples_allowed"]
      return true if raw.nil?
      ActiveModel::Type::Boolean.new.cast(raw)
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

    # The exhibition-wall image drawn from the photographer's hang (see
    # ProjectHang), placed at the top of the post. Optional: without it the
    # post keeps the Project Overview grid.
    def hang_image_upload
      id = data["hang_image_upload_id"].to_i
      id.zero? ? nil : Upload.find_by(id: id)
    end

    # Pictures of the proposed orders (see ProjectHang), in the orders' order.
    def hang_order_image_uploads
      ids =
        Array(data["hang_order_image_upload_ids"])
          .map(&:to_i)
          .select(&:positive?)
          .first(ProjectHang::MAX_EXTRA_ORDERS)
      return [] if ids.empty?
      uploads = Upload.where(id: ids).index_by(&:id)
      ids.filter_map { |id| uploads[id] }
    end

    # The proposed orders that are valid for this submission's images, each
    # with its picture when one was drawn:
    # [{ name:, numbers: ["9", "8", …], upload: Upload | nil }]
    def proposed_orders
      hang = project_hang
      orders = Array(hang && hang[:orders])
      return [] if orders.empty?

      ids = image_entries.map { |entry| entry[:upload].id }
      pictures = Array(data["hang_order_image_upload_ids"]).map(&:to_i)
      uploads = hang_order_image_uploads.index_by(&:id)
      orders.each_with_index.filter_map do |order, index|
        next unless order[:ids].sort == ids.sort
        {
          name: order[:name].presence || "Option #{("B".ord + index).chr}",
          numbers: order[:ids].map { |id| (ids.index(id) + 1).to_s },
          upload: uploads[pictures[index]],
        }
      end
    end

    def project_hang
      ProjectHang.from_submission(self)
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
        hang_image_upload,
        *hang_order_image_uploads,
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

# == Schema Information
#
# Table name: npn_submissions
#
#  id              :bigint           not null, primary key
#  client_timezone :string
#  critique_style  :string
#  data            :jsonb            not null
#  error_message   :text
#  status          :string           default("draft"), not null
#  submission_type :string           not null
#  submitted_at    :datetime
#  title           :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  topic_id        :bigint
#  user_id         :bigint           not null
#
# Indexes
#
#  index_npn_submissions_on_status                               (status)
#  index_npn_submissions_on_submission_type                      (submission_type)
#  index_npn_submissions_on_topic_id                             (topic_id)
#  index_npn_submissions_on_user_id                              (user_id)
#  index_npn_submissions_on_user_id_and_status_and_submitted_at  (user_id,status,submitted_at)
#
