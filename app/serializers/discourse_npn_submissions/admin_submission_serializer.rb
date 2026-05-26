# frozen_string_literal: true

module DiscourseNpnSubmissions
  class AdminSubmissionSerializer < SubmissionSerializer
    attributes :user_id, :username, :method

    def username
      object.user&.username
    end

    # Project submission method (images / pdf / url); blank for other types.
    def method
      object.project_method
    end
  end
end
