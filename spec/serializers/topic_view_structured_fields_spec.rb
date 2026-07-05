# frozen_string_literal: true

require "rails_helper"

# The photographer's STRUCTURED request/narrative fields are exposed on topic
# view, sourced live from the submission row (never shadowed into custom
# fields), so discourse-npn-critique-reply can pin the "Feedback Requested"
# ask and build its notes panel from structured sections.
describe TopicViewSerializer do
  fab!(:user)
  fab!(:topic) { Fabricate(:topic, user: user) }
  fab!(:post) { Fabricate(:post, topic: topic, user: user) }

  before { SiteSetting.npn_submissions_enabled = true }

  def serialized(viewer = user)
    TopicViewSerializer.new(
      TopicView.new(topic.id, viewer),
      scope: Guardian.new(viewer),
      root: false,
    ).as_json
  end

  # Marks the topic as a submission (the cheap guard the serializer checks
  # before touching the DB).
  def mark_submission_topic!
    topic.upsert_custom_fields(
      DiscourseNpnSubmissions::TopicMetadata::SUBMISSION_TYPE_KEY => "image_critique",
    )
  end

  def create_submission!(fields:, critique_style: "standard")
    DiscourseNpnSubmissions::Submission.create!(
      user_id: user.id,
      submission_type: "image",
      critique_style: critique_style,
      status: "submitted",
      topic_id: topic.id,
      data: {
        "feedback_focus" => "technical",
        "fields" => fields,
      },
    )
  end

  it "exposes the structured fields from the submission row" do
    mark_submission_topic!
    create_submission!(
      critique_style: "in_depth",
      fields: {
        "feedback_requested" => "Where does the eye go first?",
        "about_this_image" => "Shot at dawn in the aspens.",
        "technical_details" => "Z9, 400mm f/5.6",
        "creative_intent" => "The stillness of first light.",
      },
    )

    data = serialized
    expect(data[:npn_feedback_requested]).to eq("Where does the eye go first?")
    expect(data[:npn_about_this_image]).to eq("Shot at dawn in the aspens.")
    expect(data[:npn_technical_details]).to eq("Z9, 400mm f/5.6")
    expect(data[:npn_creative_intent]).to eq("The stillness of first light.")
  end

  it "returns nil for optional fields the photographer left blank" do
    mark_submission_topic!
    create_submission!(fields: { "feedback_requested" => "Balanced?" })

    data = serialized
    expect(data[:npn_feedback_requested]).to eq("Balanced?")
    # Present-but-blank: the row exists so the keys are serialized, as nil.
    expect(data.key?(:npn_about_this_image)).to eq(true)
    expect(data[:npn_about_this_image]).to be_nil
    expect(data[:npn_technical_details]).to be_nil
  end

  it "omits the fields entirely when the topic has no submission row" do
    mark_submission_topic!

    data = serialized
    expect(data.key?(:npn_feedback_requested)).to eq(false)
    expect(data.key?(:npn_about_this_image)).to eq(false)
  end

  it "omits the fields for non-submission topics without querying the row" do
    # No submission-type custom field → the guard short-circuits, so even a
    # stray row for this topic is never exposed.
    create_submission!(fields: { "feedback_requested" => "leak?" })

    data = serialized
    expect(data.key?(:npn_feedback_requested)).to eq(false)
  end

  it "falls back to the New Members Area 'feedback' key for the pinned ask" do
    # The new-member image form stores the same intent under `feedback`
    # (its heading is "Feedback Welcome"). The critique workspace reads
    # npn_feedback_requested, so it must resolve from `feedback` too.
    mark_submission_topic!
    DiscourseNpnSubmissions::Submission.create!(
      user_id: user.id,
      submission_type: "new_member_image",
      status: "submitted",
      topic_id: topic.id,
      data: { "fields" => { "feedback" => "Is the composition working?" } },
    )

    data = serialized
    expect(data[:npn_feedback_requested]).to eq("Is the composition working?")
  end

  it "prefers feedback_requested over feedback when both are present" do
    mark_submission_topic!
    create_submission!(fields: { "feedback_requested" => "canonical", "feedback" => "fallback" })

    data = serialized
    expect(data[:npn_feedback_requested]).to eq("canonical")
  end
end
