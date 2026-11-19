# frozen_string_literal: true

require "rails_helper"

describe "Editing a submission through the form" do
  fab!(:group)
  fab!(:user) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:other_user) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:category)
  fab!(:upload) { Fabricate(:upload, user: user) }
  fab!(:new_upload) { Fabricate(:upload, user: user) }
  fab!(:tag_landscape) { Fabricate(:tag, name: "landscape") }

  before do
    SiteSetting.tagging_enabled = true
    SiteSetting.npn_submissions_enabled = true
    SiteSetting.npn_submissions_allowed_groups = group.id.to_s
    SiteSetting.npn_submissions_critique_category_id = category.id.to_s
    group.add(user)
    group.add(other_user)
  end

  def payload(question: "Does it work?", upload_id: upload.id)
    {
      submission_type: "image",
      critique_style: "standard",
      title: "Please critique my landscape",
      data: {
        feedback_focus: "artistic",
        images: [{ upload_id: upload_id, note: "" }],
        tags: %w[landscape],
        fields: {
          feedback_requested: question,
        },
      },
    }
  end

  let!(:submission) do
    attrs = payload
    DiscourseNpnSubmissions::Submitter.call(
      user: user,
      attrs: attrs.merge(data: attrs[:data].deep_stringify_keys),
    )
  end

  describe "GET /npn-submissions/submissions/:id/edit" do
    it "returns the submission and the edit state to its author" do
      sign_in(user)
      get "/npn-submissions/submissions/#{submission.id}/edit.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["submission"]["id"]).to eq(submission.id)
      expect(response.parsed_body["submission"]["images"].first["id"]).to eq(upload.id)
      expect(response.parsed_body["images_locked"]).to eq(false)
      expect(response.parsed_body["edited_outside_form"]).to eq(false)
    end

    it "is forbidden to other members" do
      sign_in(other_user)
      get "/npn-submissions/submissions/#{submission.id}/edit.json"
      expect(response.status).to eq(403)
    end

    it "requires login" do
      get "/npn-submissions/submissions/#{submission.id}/edit.json"
      expect(response.status).to eq(403)
    end
  end

  describe "PUT /npn-submissions/submissions/:id" do
    it "updates the post" do
      sign_in(user)
      put "/npn-submissions/submissions/#{submission.id}.json",
          params: payload(question: "Edited question?"),
          as: :json

      expect(response.status).to eq(200)
      expect(response.parsed_body["submission"]["topic_url"]).to eq("/t/#{submission.topic_id}")
      expect(Topic.find(submission.topic_id).first_post.raw).to include("Edited question?")
    end

    it "returns 422 when images are locked" do
      Fabricate(:post, topic: Topic.find(submission.topic_id), user: other_user)
      sign_in(user)
      put "/npn-submissions/submissions/#{submission.id}.json",
          params: payload(upload_id: new_upload.id),
          as: :json

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"].first).to include("Revised Version")
    end

    it "returns 409 for a post edited outside the form, and overwrites with force" do
      post = Topic.find(submission.topic_id).first_post
      post.revise(user, raw: "#{post.raw}\n\nBy hand.")
      sign_in(user)

      put "/npn-submissions/submissions/#{submission.id}.json", params: payload, as: :json
      expect(response.status).to eq(409)
      expect(response.parsed_body["edited_outside_form"]).to eq(true)

      put "/npn-submissions/submissions/#{submission.id}.json",
          params: payload.merge(force: true),
          as: :json
      expect(response.status).to eq(200)
      expect(post.reload.raw).not_to include("By hand.")
    end
  end

  describe "topic view" do
    it "exposes npn_edit_submission_id to the author only" do
      sign_in(user)
      get "/t/#{submission.topic_id}.json"
      expect(response.parsed_body["npn_edit_submission_id"]).to eq(submission.id)

      sign_in(other_user)
      get "/t/#{submission.topic_id}.json"
      expect(response.parsed_body).not_to have_key("npn_edit_submission_id")
    end
  end
end
