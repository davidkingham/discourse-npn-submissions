# frozen_string_literal: true

require "rails_helper"

# `npn_project_images` feeds the reply composer's project strip and the
# Suggest-a-Sequence builder: numbered originals (by submission position) and
# A-numbered alternates, for image-method projects only.
describe TopicViewSerializer do
  fab!(:user)
  fab!(:topic) { Fabricate(:topic, user: user) }
  fab!(:post) { Fabricate(:post, topic: topic, user: user) }
  fab!(:upload1) do
    Fabricate(
      :upload,
      user: user,
      width: 1200,
      height: 800,
      thumbnail_width: nil,
      thumbnail_height: nil,
    )
  end
  fab!(:upload2) { Fabricate(:upload, user: user, width: 800, height: 1200) }
  fab!(:alternate) { Fabricate(:upload, user: user, width: 1000, height: 1000) }

  before do
    SiteSetting.npn_submissions_enabled = true
    topic.upsert_custom_fields(
      DiscourseNpnSubmissions::TopicMetadata::SUBMISSION_TYPE_KEY => "project_critique",
    )
  end

  def serialized
    TopicViewSerializer.new(
      TopicView.new(topic.id, user),
      scope: Guardian.new(user),
      root: false,
    ).as_json
  end

  def create_project!(data)
    DiscourseNpnSubmissions::Submission.create!(
      user_id: user.id,
      submission_type: "project",
      status: "submitted",
      topic_id: topic.id,
      data: data,
    )
  end

  it "exposes numbered originals and A-numbered alternates in order" do
    create_project!(
      "method" => "images",
      "images" => [
        { "upload_id" => upload1.id, "note" => "Opening frame" },
        { "upload_id" => upload2.id, "note" => "" },
      ],
      "alternates" => [{ "upload_id" => alternate.id, "note" => "" }],
    )

    images = serialized[:npn_project_images]
    originals = images[:originals]
    expect(originals.map { |i| i[:number] }).to eq(%w[1 2])
    expect(originals.map { |i| i[:upload_id] }).to eq([upload1.id, upload2.id])
    expect(originals.first[:short_url]).to eq(upload1.short_url)
    expect(originals.first[:caption]).to eq("Opening frame")
    expect(originals.second[:caption]).to be_nil
    expect(originals.first[:width]).to eq(1200)
    expect(originals.first[:height]).to eq(800)
    # No optimized rendition exists for a fabricated upload → client falls
    # back to the original URL.
    expect(originals.first).to have_key(:sheet_url)
    expect(originals.first[:sheet_url]).to be_nil

    expect(images[:alternates].map { |i| i[:number] }).to eq(%w[A1])
    expect(originals.first[:original_width]).to eq(1200)
    expect(images[:feedback_types]).to eq([])
    expect(images[:alternates].first[:upload_id]).to eq(alternate.id)
  end

  it "includes the requested feedback types and presentation goal" do
    create_project!(
      "method" => "images",
      "images" => [{ "upload_id" => upload1.id }],
      "feedback_types" => %w[individual sequence],
      "fields" => {
        "project_intent" => "book",
      },
    )

    images = serialized[:npn_project_images]
    expect(images[:feedback_types]).to eq(%w[sequence individual])
    expect(images[:intent]).to eq("book")
  end

  it "carries the stable slot id from the structured project payload" do
    create_project!("method" => "images", "images" => [{ "upload_id" => upload1.id }])
    topic.upsert_custom_fields(
      DiscourseNpnSubmissions::TopicMetadata::PROJECT_SUBMISSION_DATA_KEY => {
        "images" => [{ "id" => "abc123", "position" => 1 }],
      }.to_json,
    )

    expect(serialized[:npn_project_images][:originals].first[:slot_id]).to eq("abc123")
  end

  it "is nil for PDF projects" do
    create_project!("method" => "pdf")
    expect(serialized[:npn_project_images]).to be_nil
  end

  it "is omitted for non-project submissions" do
    DiscourseNpnSubmissions::Submission.create!(
      user_id: user.id,
      submission_type: "image",
      critique_style: "standard",
      status: "submitted",
      topic_id: topic.id,
      data: {
        "images" => [{ "upload_id" => upload1.id }],
      },
    )
    expect(serialized.key?(:npn_project_images)).to eq(false)
  end

  it "is omitted when the topic has no submission row" do
    expect(serialized.key?(:npn_project_images)).to eq(false)
  end

  describe "fallback for tagged project topics without a submission row" do
    fab!(:project_tag) { Fabricate(:tag, name: "project") }

    def raw_with_sequence
      "### Image Sequence\n\n![Image 1](#{upload1.short_url})\n\n![Image 2](#{upload2.short_url})\n"
    end

    before do
      topic.custom_fields.clear
      TopicCustomField.where(topic_id: topic.id).delete_all
      post.update_columns(raw: raw_with_sequence)
    end

    it "reads the images from the first post when the topic has the tag" do
      topic.tags = [project_tag]
      topic.save!

      images = serialized[:npn_project_images]
      expect(images[:source]).to eq("post")
      expect(images[:originals].map { |i| i[:upload_id] }).to eq([upload1.id, upload2.id])
    end

    it "is omitted without the tag" do
      expect(serialized.key?(:npn_project_images)).to eq(false)
    end

    it "is omitted when the fallback tag setting is blank" do
      SiteSetting.npn_submissions_project_fallback_tag = ""
      topic.tags = [project_tag]
      topic.save!
      expect(serialized.key?(:npn_project_images)).to eq(false)
    end
  end
end
