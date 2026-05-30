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

# == Schema Information
#
# Table name: npn_submission_uploads
#
#  id            :bigint           not null, primary key
#  position      :integer          default(0), not null
#  role          :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  submission_id :bigint           not null
#  upload_id     :bigint           not null
#
# Indexes
#
#  idx_npn_submission_uploads_ordering            (submission_id,role,position) UNIQUE
#  index_npn_submission_uploads_on_submission_id  (submission_id)
#  index_npn_submission_uploads_on_upload_id      (upload_id)
#
