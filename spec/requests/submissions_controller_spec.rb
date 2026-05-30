# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnSubmissions::SubmissionsController do
  fab!(:group)
  fab!(:user)
  fab!(:category)
  fab!(:upload) { Fabricate(:upload, user: user) }
  fab!(:tag_landscape) { Fabricate(:tag, name: "landscape") }

  before do
    SiteSetting.tagging_enabled = true
    SiteSetting.npn_submissions_enabled = true
    SiteSetting.npn_submissions_allowed_groups = group.id.to_s
    SiteSetting.npn_submissions_critique_category_id = category.id.to_s
    group.add(user)
  end

  def payload(overrides = {})
    {
      submission_type: "image",
      critique_style: "standard",
      title: "Please critique my landscape",
      data: {
        feedback_focus: "artistic",
        images: [{ upload_id: upload.id, note: "" }],
        tags: ["landscape"],
        fields: {
          feedback_requested: "Does the composition feel balanced?",
        },
      },
    }.merge(overrides)
  end

  describe "POST #preview" do
    it "returns markdown and cooked HTML without creating a draft or topic" do
      sign_in(user)

      expect { post "/npn-submissions/preview.json", params: payload, as: :json }.not_to change {
        [DiscourseNpnSubmissions::Submission.count, Topic.count]
      }

      expect(response.status).to eq(200)
      body = response.parsed_body
      expect(body["markdown"]).to include("### Feedback Requested")
      expect(body["cooked"]).to include("<h3")
      expect(body["cooked"]).to include("<img")
      # The critique guidance card survives cooking (allowlisted), so the preview
      # modal renders the same quiet card as the final post.
      expect(body["cooked"]).to include("npn-critique-guidance")
    end

    it "applies the weekly challenge tag for weekly submissions" do
      Fabricate(:tag, name: "weekly-challenge")
      SiteSetting.npn_submissions_weekly_challenge_tag = "weekly-challenge"
      sign_in(user)

      post "/npn-submissions/preview.json",
           params: payload(submission_type: "weekly_challenge"),
           as: :json

      expect(response.status).to eq(200)
      expect(response.parsed_body["tags"]).to include("weekly-challenge", "landscape")
    end

    it "includes the synced weekly challenge title in the preview markdown" do
      Fabricate(:tag, name: "weekly-challenge")
      SiteSetting.npn_submissions_weekly_challenge_tag = "weekly-challenge"
      allow(DiscourseNpnSubmissions::WeeklyChallengeInfo).to receive(:current).and_return(
        { title: "Quiet Geometry", dates: "May 20–26, 2026", description: nil, url: nil },
      )
      sign_in(user)

      post "/npn-submissions/preview.json",
           params: payload(submission_type: "weekly_challenge"),
           as: :json

      expect(response.status).to eq(200)
      body = response.parsed_body
      expect(body["markdown"]).to include(
        '<div class="npn-weekly-challenge-title">Quiet Geometry</div>',
      )
      expect(body["markdown"]).to include(
        '<div class="npn-weekly-challenge-dates">May 20–26, 2026</div>',
      )
      # The scoped wrapper survives cooking (allowlisted), so the preview modal —
      # which cooks the same Markdown — matches the final post.
      expect(body["cooked"]).to include("npn-weekly-challenge-context")
      expect(body["cooked"]).to include("Quiet Geometry")
    end

    it "returns a validation error for an incomplete post" do
      sign_in(user)

      post "/npn-submissions/preview.json",
           params: payload(data: payload[:data].merge(tags: [])),
           as: :json

      expect(response.status).to eq(422)
    end

    it "forbids users who cannot submit" do
      sign_in(user)
      group.remove(user)

      post "/npn-submissions/preview.json", params: payload, as: :json
      expect(response.status).to eq(403)
    end

    it "requires authentication" do
      post "/npn-submissions/preview.json", params: payload, as: :json
      expect(response.status).to eq(403)
    end

    it "does not invoke the weekly challenge sync for a standard image preview" do
      sign_in(user)
      allow(DiscourseNpnSubmissions::WeeklyChallengeInfo).to receive(:current)

      post "/npn-submissions/preview.json", params: payload, as: :json

      expect(response.status).to eq(200)
      expect(DiscourseNpnSubmissions::WeeklyChallengeInfo).not_to have_received(:current)
    end

    it "returns a structured JSON error (not a raw 500) if building the post raises" do
      sign_in(user)
      allow(DiscourseNpnSubmissions::PostBuilder).to receive(:build).and_raise(
        NoMethodError.new("boom"),
      )

      post "/npn-submissions/preview.json", params: payload, as: :json

      expect(response.status).to eq(500)
      expect(response.parsed_body["errors"]).to be_present
    end
  end

  describe "POST #preview (project)" do
    before do
      SiteSetting.npn_submissions_project_category_id = category.id.to_s
      SiteSetting.npn_submissions_project_tag = "project"
      Fabricate(:tag, name: "project")
    end

    def project_payload
      {
        submission_type: "project",
        title: "My Landscape Project for Critique",
        data: {
          method: "images",
          feedback_focus: "artistic",
          images: [{ upload_id: upload.id }],
          tags: ["landscape"],
          fields: {
            project_description: "A cohesive body of work.",
            self_critique: "Working and improving.",
            creative_direction: "Quiet mood.",
            feedback_requested: "Does it cohere?",
            project_intent: "gallery",
          },
        },
      }
    end

    it "returns the project post markdown and applied tags" do
      sign_in(user)
      post "/npn-submissions/preview.json", params: project_payload, as: :json

      expect(response.status).to eq(200)
      body = response.parsed_body
      expect(body["markdown"]).to include("### Brief Project Description")
      expect(body["markdown"]).to include("### Project Overview")
      expect(body["markdown"]).to include("### Image Sequence")
      # The overview grid markup survives cooking (allowlisted), so the preview
      # modal matches the final post.
      expect(body["cooked"]).to include("npn-project-overview-grid")
      expect(body["cooked"]).to include("npn-project-overview-frame")
      expect(body["cooked"]).to include("npn-project-overview-label")
      expect(body["tags"]).to include("project", "landscape")
    end
  end

  describe "GET #weekly_challenge" do
    it "returns the synced challenge when sync is available" do
      allow(DiscourseNpnSubmissions::WeeklyChallengeInfo).to receive(:current).and_return(
        {
          title: "Quiet Geometry",
          dates: "May 20–26, 2026",
          description: "Shapes.",
          url: "https://e/c",
        },
      )
      sign_in(user)

      get "/npn-submissions/weekly-challenge.json"

      expect(response.status).to eq(200)
      challenge = response.parsed_body["challenge"]
      expect(challenge["title"]).to eq("Quiet Geometry")
      expect(challenge["dates"]).to eq("May 20–26, 2026")
    end

    it "returns null when sync is unavailable" do
      allow(DiscourseNpnSubmissions::WeeklyChallengeInfo).to receive(:current).and_return(nil)
      sign_in(user)

      get "/npn-submissions/weekly-challenge.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["challenge"]).to be_nil
    end

    it "requires authentication" do
      get "/npn-submissions/weekly-challenge.json"
      expect(response.status).to eq(403)
    end
  end

  describe "GET #descriptive_tags" do
    it "reports unconstrained when no tag group is configured" do
      sign_in(user)
      get "/npn-submissions/descriptive-tags.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["constrained"]).to eq(false)
    end

    it "returns the configured group's tags when constrained" do
      group = Fabricate(:tag_group, name: "critique-subjects")
      group.tags = [tag_landscape]
      SiteSetting.npn_submissions_descriptive_tag_group = "critique-subjects"

      sign_in(user)
      get "/npn-submissions/descriptive-tags.json"

      expect(response.parsed_body["constrained"]).to eq(true)
      expect(response.parsed_body["tags"]).to include("landscape")
    end
  end

  describe "GET #daily_limit" do
    before do
      SiteSetting.npn_submissions_enforce_daily_limit = true
      sign_in(user)
    end

    def submitted_today!
      DiscourseNpnSubmissions::Submission.create!(
        user_id: user.id,
        submission_type: "image",
        status: "submitted",
        submitted_at: Time.zone.now,
      )
    end

    it "reports false when the user has not submitted today" do
      get "/npn-submissions/daily-limit.json", params: { tz: "America/Denver" }

      expect(response.status).to eq(200)
      expect(response.parsed_body["limit_reached"]).to eq(false)
    end

    it "reports true after the user submits today" do
      submitted_today!
      get "/npn-submissions/daily-limit.json", params: { tz: "America/Denver" }

      expect(response.parsed_body["limit_reached"]).to eq(true)
    end

    it "reports false when enforcement is disabled" do
      SiteSetting.npn_submissions_enforce_daily_limit = false
      submitted_today!
      get "/npn-submissions/daily-limit.json", params: { tz: "America/Denver" }

      expect(response.parsed_body["limit_reached"]).to eq(false)
    end
  end
end
