# frozen_string_literal: true

module DiscourseNpnSubmissions
  module Admin
    class SubmissionsController < ::Admin::AdminController
      requires_plugin DiscourseNpnSubmissions::PLUGIN_NAME

      def index
        render_json_dump(
          counts: {
            drafts: DiscourseNpnSubmissions::Submission.drafts.count,
            submitted: DiscourseNpnSubmissions::Submission.submitted.count,
            failed: DiscourseNpnSubmissions::Submission.failed.count
          }
        )
      end

      def drafts
        render_json_dump(
          submissions:
            serialize_data(recent(Submission.drafts), AdminSubmissionSerializer)
        )
      end

      def failed
        render_json_dump(
          submissions:
            serialize_data(recent(Submission.failed), AdminSubmissionSerializer)
        )
      end

      private

      def recent(scope)
        scope.includes(:user).order(updated_at: :desc).limit(100)
      end
    end
  end
end
