# frozen_string_literal: true

require "rails_helper"

# The processing-examples preference is exposed on topic view so
# discourse-npn-critique-reply can show/hide its Processing Example controls.
describe TopicViewSerializer do
  fab!(:user)
  fab!(:topic) { Fabricate(:topic, user: user) }
  fab!(:post) { Fabricate(:post, topic: topic, user: user) }

  def serialized(viewer = user)
    TopicViewSerializer.new(
      TopicView.new(topic.id, viewer),
      scope: Guardian.new(viewer),
      root: false,
    ).as_json
  end

  it "exposes the stored opt-out as a real boolean" do
    DiscourseNpnSubmissions::TopicMetadata.save(
      topic,
      { "npn_processing_examples_allowed" => false },
    )
    expect(serialized[:npn_processing_examples_allowed]).to eq(false)
  end

  it "exposes an explicit allowed value" do
    DiscourseNpnSubmissions::TopicMetadata.save(
      topic,
      { "npn_processing_examples_allowed" => true },
    )
    expect(serialized[:npn_processing_examples_allowed]).to eq(true)
  end

  it "treats a missing field as allowed (true) for older critique topics" do
    expect(serialized[:npn_processing_examples_allowed]).to eq(true)
  end
end
