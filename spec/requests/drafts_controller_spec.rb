# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnSubmissions::DraftsController do
  fab!(:group)
  fab!(:user)
  fab!(:other_user, :user)

  before do
    SiteSetting.npn_submissions_enabled = true
    SiteSetting.npn_submissions_allowed_groups = group.id.to_s
    group.add(user)
  end

  describe "GET #index" do
    it "returns the user's own drafts under a `drafts` root, with hydrated images" do
      upload = Fabricate(:upload, user: user)
      DiscourseNpnSubmissions::DraftStore.create(
        user,
        submission_type: "image",
        title: "My draft",
        data: {
          "images" => [{ "upload_id" => upload.id, "note" => "wide crop" }],
        },
      )

      sign_in(user)
      get "/npn-submissions/drafts.json"

      expect(response.status).to eq(200)
      drafts = response.parsed_body["drafts"]
      expect(drafts.size).to eq(1)

      draft = drafts.first
      expect(draft["title"]).to eq("My draft")

      image = draft["images"].first
      expect(image["id"]).to eq(upload.id)
      expect(image["url"]).to be_present
      expect(image["note"]).to eq("wide crop")
    end

    it "preserves the submission_type so weekly challenge drafts are distinguishable" do
      DiscourseNpnSubmissions::DraftStore.create(
        user,
        submission_type: "weekly_challenge",
        title: "WC draft",
      )

      sign_in(user)
      get "/npn-submissions/drafts.json"

      draft = response.parsed_body["drafts"].find { |d| d["title"] == "WC draft" }
      expect(draft["submission_type"]).to eq("weekly_challenge")
    end

    it "preserves project submission_type and method for project drafts" do
      DiscourseNpnSubmissions::DraftStore.create(
        user,
        submission_type: "project",
        title: "Project draft",
        data: {
          "method" => "pdf",
        },
      )

      sign_in(user)
      get "/npn-submissions/drafts.json"

      draft = response.parsed_body["drafts"].find { |d| d["title"] == "Project draft" }
      expect(draft["submission_type"]).to eq("project")
      expect(draft["data"]["method"]).to eq("pdf")
    end

    it "round-trips the processing-examples preference so the form restores it" do
      DiscourseNpnSubmissions::DraftStore.create(
        user,
        submission_type: "image",
        title: "Opted-out draft",
        data: {
          "processing_examples_allowed" => false,
        },
      )

      sign_in(user)
      get "/npn-submissions/drafts.json"

      draft = response.parsed_body["drafts"].find { |d| d["title"] == "Opted-out draft" }
      expect(draft["data"]["processing_examples_allowed"]).to eq(false)
    end

    it "does not return another user's drafts" do
      DiscourseNpnSubmissions::DraftStore.create(
        other_user,
        submission_type: "image",
        title: "Theirs",
      )

      sign_in(user)
      get "/npn-submissions/drafts.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["drafts"]).to eq([])
    end

    it "forbids users who are not allowed to submit" do
      sign_in(other_user) # signed in, but not in the allowed group

      get "/npn-submissions/drafts.json"
      expect(response.status).to eq(403)
    end

    it "requires authentication" do
      get "/npn-submissions/drafts.json"
      expect(response.status).to eq(403)
    end
  end
end
