# frozen_string_literal: true

module DiscourseNpnSubmissions
  # CRUD for a user's draft submissions. Every method is scoped to the owning
  # user, so one user can never read or mutate another user's draft. Multiple
  # drafts per user are supported.
  module DraftStore
    WRITABLE_ATTRS = %i[submission_type critique_style title data client_timezone].freeze

    # Statuses the user can resume in their form's draft panel. "draft" is
    # the normal in-progress state; "failed" lets a user recover a
    # submission that errored at create time (e.g. an upload-attach
    # failure) instead of silently losing their work. Loading a failed
    # submission re-opens the form pre-filled and lets the user resubmit.
    # The admin dashboard's "Failed" tab queries Submission.failed
    # directly and is unaffected.
    RESUMABLE_STATUSES = %w[draft failed].freeze

    module_function

    def list(user)
      Submission.for_user(user).where(status: RESUMABLE_STATUSES).order(updated_at: :desc)
    end

    # Raises ActiveRecord::RecordNotFound if the draft does not exist or is not
    # owned by `user`.
    def find(user, id)
      Submission.for_user(user).where(status: RESUMABLE_STATUSES).find(id)
    end

    def create(user, attrs)
      attrs = attrs.symbolize_keys
      Submission.create!(
        user_id: user.id,
        status: "draft",
        submission_type: attrs[:submission_type],
        critique_style: attrs[:critique_style],
        title: attrs[:title],
        data: attrs[:data] || {},
        client_timezone: attrs[:client_timezone],
      )
    end

    def update(user, id, attrs)
      draft = find(user, id)
      changes = attrs.symbolize_keys.slice(*WRITABLE_ATTRS).compact
      draft.update!(changes)
      draft
    end

    def destroy(user, id)
      find(user, id).destroy!
    end
  end
end
