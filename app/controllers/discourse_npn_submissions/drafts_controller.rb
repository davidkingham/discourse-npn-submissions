# frozen_string_literal: true

module DiscourseNpnSubmissions
  class DraftsController < ::ApplicationController
    requires_plugin DiscourseNpnSubmissions::PLUGIN_NAME

    before_action :ensure_logged_in
    before_action :ensure_can_submit

    def index
      render_serialized(
        DraftStore.list(current_user),
        SubmissionSerializer,
        root: "drafts",
      )
    end

    def create
      draft = DraftStore.create(current_user, draft_params)
      render_serialized(draft, SubmissionSerializer)
    end

    def update
      draft = DraftStore.update(current_user, params[:id], draft_params)
      render_serialized(draft, SubmissionSerializer)
    rescue ActiveRecord::RecordNotFound
      raise Discourse::NotFound
    end

    def destroy
      DraftStore.destroy(current_user, params[:id])
      render json: success_json
    rescue ActiveRecord::RecordNotFound
      raise Discourse::NotFound
    end

    private

    def ensure_can_submit
      raise Discourse::InvalidAccess unless Policy.can_submit?(current_user)
    end

    def draft_params
      permitted =
        params.permit(
          :submission_type,
          :critique_style,
          :title,
          :client_timezone,
          data: {
          }
        )
      {
        submission_type: permitted[:submission_type],
        critique_style: permitted[:critique_style],
        title: permitted[:title],
        client_timezone: permitted[:client_timezone],
        data: permitted[:data]&.to_h
      }.compact
    end
  end
end
