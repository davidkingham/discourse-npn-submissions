# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnSubmissions::Admin::SubmissionsController do
  fab!(:admin)
  fab!(:user)

  before do
    SiteSetting.npn_submissions_enabled = true
    sign_in(admin)
  end

  describe "GET #drafts" do
    it "distinguishes weekly challenge drafts from image drafts by submission_type" do
      DiscourseNpnSubmissions::DraftStore.create(
        user,
        submission_type: "image",
        title: "Image draft",
      )
      DiscourseNpnSubmissions::DraftStore.create(
        user,
        submission_type: "weekly_challenge",
        title: "Weekly draft",
      )

      get "/admin/npn-submissions/drafts.json"

      expect(response.status).to eq(200)
      types = response.parsed_body["submissions"].map { |s| s["submission_type"] }
      expect(types).to include("image", "weekly_challenge")
    end

    it "exposes the project method for project submissions" do
      DiscourseNpnSubmissions::DraftStore.create(
        user,
        submission_type: "project",
        title: "Project draft",
        data: {
          "method" => "url",
        },
      )

      get "/admin/npn-submissions/drafts.json"

      project = response.parsed_body["submissions"].find { |s| s["title"] == "Project draft" }
      expect(project["submission_type"]).to eq("project")
      expect(project["project_method"]).to eq("url")
    end
  end
end
