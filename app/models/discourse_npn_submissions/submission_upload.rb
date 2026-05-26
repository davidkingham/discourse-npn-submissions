# frozen_string_literal: true

module DiscourseNpnSubmissions
  class SubmissionUpload < ::ActiveRecord::Base
    self.table_name = "npn_submission_uploads"

    ROLES = %w[
      main
      variation
      project_image
      alternate
      pdf
      representative_image
      metadata_screenshot
    ].freeze

    belongs_to :submission,
               class_name: "DiscourseNpnSubmissions::Submission",
               foreign_key: :submission_id
    belongs_to :upload

    validates :role, presence: true, inclusion: { in: ROLES }
    validates :position,
              presence: true,
              numericality: {
                only_integer: true,
                greater_than_or_equal_to: 0,
              }
  end
end
