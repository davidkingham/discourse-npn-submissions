# frozen_string_literal: true

module DiscourseNpnSubmissions
  class AdminSubmissionSerializer < SubmissionSerializer
    attributes :user_id, :username, :project_method

    def username
      object.user&.username
    end

    # Project submission method (images / pdf / url); blank for other types.
    # Named project_method rather than `method` so it doesn't shadow Ruby's
    # Object#method — a zero-arg override breaks any `serializer.method(:x)` call.
    def project_method
      object.project_method
    end
  end
end
