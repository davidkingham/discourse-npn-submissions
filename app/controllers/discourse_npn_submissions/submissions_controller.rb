# frozen_string_literal: true

module DiscourseNpnSubmissions
  class SubmissionsController < ::ApplicationController
    requires_plugin DiscourseNpnSubmissions::PLUGIN_NAME

    before_action :ensure_logged_in,
                  only: %i[create preview daily_limit descriptive_tags weekly_challenge]

    # GET /submit
    # Renders the Ember app; the client route decides which flow to open
    # based on the `type` query parameter.
    def new
      render html: nil, layout: true
    end

    # POST /npn-submissions/submissions
    def create
      submission =
        Submitter.call(
          user: current_user,
          draft_id: params[:draft_id],
          attrs: submission_params,
          tz_name: params[:client_timezone]
        )
      render_serialized(submission, SubmissionSerializer)
    rescue Submitter::NotAllowed
      render_json_error(
        I18n.t("npn_submissions.errors.not_allowed"),
        status: 403
      )
    rescue Submitter::InvalidType
      render_json_error(
        I18n.t("npn_submissions.errors.invalid_type"),
        status: 422
      )
    rescue Submitter::InvalidSubmission => e
      render_json_error(e.message, status: 422)
    rescue DailyLimit::Exceeded
      render_json_error(
        I18n.t("npn_submissions.errors.daily_limit_reached"),
        status: 422
      )
    rescue Submitter::CreationFailed => e
      render_json_error(e.message, status: 422)
    rescue => e
      log_unexpected("create", e)
      render_json_error(I18n.t("npn_submissions.errors.unexpected"), status: 500)
    end

    # POST /npn-submissions/preview
    # Builds the post markdown/cooked HTML for the submitted form without saving a
    # draft, creating uploads or a topic, or counting against the daily limit.
    def preview
      result =
        Submitter.preview(
          user: current_user,
          attrs: submission_params,
          tz_name: params[:client_timezone]
        )
      render json: {
               markdown: result[:markdown],
               cooked: PrettyText.cook(result[:markdown]),
               tags: result[:tags]
             }
    rescue Submitter::NotAllowed
      render_json_error(I18n.t("npn_submissions.errors.not_allowed"), status: 403)
    rescue Submitter::InvalidType
      render_json_error(I18n.t("npn_submissions.errors.invalid_type"), status: 422)
    rescue Submitter::InvalidSubmission => e
      render_json_error(e.message, status: 422)
    rescue => e
      # Any unexpected error (e.g. a post-builder bug) must still return JSON, not
      # a raw HTML 500 the client can't parse. Logged with a backtrace so the real
      # cause is debuggable server-side.
      log_unexpected("preview", e)
      render_json_error(I18n.t("npn_submissions.errors.preview_failed"), status: 500)
    end

    # GET /npn-submissions/daily-limit
    # Whether the current user has already used their daily critique submission,
    # evaluated in the browser timezone (`tz`). Lets the form warn up front while
    # still allowing drafts; never blocks draft creation.
    def daily_limit
      render json: {
               limit_reached:
                 DailyLimit.reached?(user: current_user, tz_name: params[:tz])
             }
    end

    # GET /npn-submissions/descriptive-tags
    # The descriptive tags the submitter may choose from. When a tag group is
    # configured the choices are constrained to that group's tags; otherwise the
    # client falls back to the normal tag chooser (any existing tag).
    def descriptive_tags
      render json: {
               constrained: Policy.descriptive_tags_constrained?,
               tags: Policy.allowed_descriptive_tag_names.sort
             }
    end

    # GET /npn-submissions/weekly-challenge
    # Current Weekly Challenge info synced from WordPress (cached server-side), or
    # null when sync is unavailable/unconfigured so the panel uses its static
    # fallback. Public challenge info only; never blocks the form on failure.
    def weekly_challenge
      render json: { challenge: WeeklyChallengeInfo.current }
    end

    private

    # Discourse.warn_exception is the idiomatic exception logger for plugins —
    # it talks to Logster with the proper add_with_opts API (passing the
    # backtrace as a separate kwarg rather than stuffing it into the message
    # body, which Logster's processor doesn't tolerate) and has its own rescue
    # so a logger backend failure can never escape this method and turn our
    # structured JSON 500 into a raw HTML 500. The outer rescue here is
    # defence in depth.
    def log_unexpected(action, error)
      Discourse.warn_exception(
        error,
        message: "[discourse-npn-submissions] #{action} failed",
      )
    rescue StandardError
      begin
        Rails.logger.warn("[discourse-npn-submissions] #{action} failed: #{error.class}")
      rescue StandardError
        nil
      end
    end

    def submission_params
      permitted =
        params.permit(:submission_type, :critique_style, :title, data: {})
      {
        submission_type: permitted[:submission_type],
        critique_style: permitted[:critique_style],
        title: permitted[:title],
        data: permitted[:data].to_h
      }
    end
  end
end
