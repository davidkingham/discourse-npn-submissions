# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnSubmissions::TopicMetadata do
  fab!(:user)
  fab!(:upload) { Fabricate(:upload, user: user) }

  def submission(overrides = {})
    DiscourseNpnSubmissions::Submission.new(
      {
        user_id: user.id,
        submission_type: "image",
        status: "submitted",
        critique_style: "standard",
        title: "My Image",
        data: {
          "feedback_focus" => "artistic",
          "images" => [{ "upload_id" => upload.id, "note" => "" }],
        },
      }.merge(overrides),
    )
  end

  describe ".build" do
    it "stores schema version and submission type for an Image Critique" do
      meta =
        described_class.build(
          submission(submission_type: "image", critique_style: "standard"),
        )

      expect(meta).to include(
        "npn_submission_schema_version" => 1,
        "npn_submission_type" => "image_critique",
        "npn_critique_style" => "standard",
        "npn_feedback_focus" => "artistic_expressive",
      )
      # No weekly fields for an image submission.
      expect(meta.keys).not_to include(
        "npn_wordpress_challenge_id",
        "npn_weekly_challenge_title",
        "npn_weekly_challenge_dates",
        "npn_wordpress_challenge_url",
      )
    end

    it "normalizes 'reaction' critique style to 'initial_reaction'" do
      meta = described_class.build(submission(critique_style: "reaction"))
      expect(meta["npn_critique_style"]).to eq("initial_reaction")
    end

    it "normalizes 'both' feedback focus to 'artistic_technical'" do
      sub = submission
      sub.data["feedback_focus"] = "both"
      expect(described_class.build(sub)["npn_feedback_focus"]).to eq("artistic_technical")
    end

    it "stores schema, type, critique style, focus, and synced challenge identity for Weekly" do
      allow(DiscourseNpnSubmissions::WeeklyChallengeInfo).to receive(:current).and_return(
        {
          id: 1241,
          title: "Celebrating Biodiversity",
          dates: "5/24/26 - 5/30/26",
          description: "ignored — never stored here",
          url: "https://www.naturephotographers.network/weekly-challenge/1241/",
        },
      )

      meta =
        described_class.build(
          submission(submission_type: "weekly_challenge", critique_style: "in_depth"),
        )

      expect(meta).to include(
        "npn_submission_schema_version" => 1,
        "npn_submission_type" => "weekly_challenge",
        "npn_critique_style" => "in_depth",
        "npn_feedback_focus" => "artistic_expressive",
        "npn_wordpress_challenge_id" => 1241,
        "npn_weekly_challenge_title" => "Celebrating Biodiversity",
        "npn_weekly_challenge_dates" => "5/24/26 - 5/30/26",
        "npn_wordpress_challenge_url" =>
          "https://www.naturephotographers.network/weekly-challenge/1241/",
      )
    end

    it "stores type and schema for a Project Critique and omits critique style" do
      sub =
        submission(
          submission_type: "project",
          critique_style: nil,
          data: {
            "method" => "images",
            "feedback_focus" => "both",
            "fields" => {
            },
          },
        )

      meta = described_class.build(sub)

      expect(meta).to include(
        "npn_submission_schema_version" => 1,
        "npn_submission_type" => "project_critique",
        "npn_feedback_focus" => "artistic_technical",
      )
      expect(meta.keys).not_to include("npn_critique_style")
    end

    it "includes feedback focus on a project when it's a known enum value" do
      sub =
        submission(
          submission_type: "project",
          critique_style: nil,
          data: {
            "method" => "images",
            "feedback_focus" => "technical",
          },
        )
      expect(described_class.build(sub)["npn_feedback_focus"]).to eq("technical_help")
    end

    it "omits feedback focus on a project when the value is unknown" do
      sub =
        submission(
          submission_type: "project",
          critique_style: nil,
          data: {
            "method" => "images",
            "feedback_focus" => "something_made_up",
          },
        )
      expect(described_class.build(sub).keys).not_to include("npn_feedback_focus")
    end

    it "omits a critique style that isn't in the known enum" do
      sub =
        DiscourseNpnSubmissions::Submission.new(
          user_id: user.id,
          submission_type: "image",
          status: "submitted",
          critique_style: nil,  # not a known value
          title: "x",
          data: {
            "feedback_focus" => "artistic",
          },
        )
      expect(described_class.build(sub).keys).not_to include("npn_critique_style")
    end

    it "omits the weekly challenge identity fields when sync returns nil" do
      allow(DiscourseNpnSubmissions::WeeklyChallengeInfo).to receive(:current).and_return(nil)
      meta = described_class.build(submission(submission_type: "weekly_challenge"))

      expect(meta.keys).not_to include(
        "npn_wordpress_challenge_id",
        "npn_weekly_challenge_title",
        "npn_weekly_challenge_dates",
        "npn_wordpress_challenge_url",
      )
      # The schema + type + style + focus are still recorded.
      expect(meta).to include(
        "npn_submission_schema_version" => 1,
        "npn_submission_type" => "weekly_challenge",
      )
    end

    it "omits partial weekly identity fields individually when missing" do
      allow(DiscourseNpnSubmissions::WeeklyChallengeInfo).to receive(:current).and_return(
        { id: nil, title: "Just a title", dates: nil, description: nil, url: nil },
      )
      meta = described_class.build(submission(submission_type: "weekly_challenge"))

      expect(meta).to include("npn_weekly_challenge_title" => "Just a title")
      expect(meta.keys).not_to include(
        "npn_wordpress_challenge_id",
        "npn_weekly_challenge_dates",
        "npn_wordpress_challenge_url",
      )
    end

    it "trims whitespace from synced string values" do
      allow(DiscourseNpnSubmissions::WeeklyChallengeInfo).to receive(:current).and_return(
        { id: 7, title: "  Quiet Geometry  ", dates: "\tMay 20–26\t", description: "x", url: "https://e.com/c" },
      )
      meta = described_class.build(submission(submission_type: "weekly_challenge"))

      expect(meta["npn_weekly_challenge_title"]).to eq("Quiet Geometry")
      expect(meta["npn_weekly_challenge_dates"]).to eq("May 20–26")
    end

    it "length-caps long synced string values" do
      long_title = "x" * 500
      allow(DiscourseNpnSubmissions::WeeklyChallengeInfo).to receive(:current).and_return(
        { id: 7, title: long_title, dates: nil, description: nil, url: nil },
      )
      meta = described_class.build(submission(submission_type: "weekly_challenge"))

      expect(meta["npn_weekly_challenge_title"].length).to be <= described_class::MAX_TITLE
    end
  end

  describe ".save" do
    fab!(:category)
    fab!(:topic) { Fabricate(:topic, category: category, user: user) }

    it "writes metadata as topic custom fields" do
      meta = {
        "npn_submission_schema_version" => 1,
        "npn_submission_type" => "image_critique",
        "npn_critique_style" => "standard",
      }

      described_class.save(topic, meta)
      topic.reload

      expect(topic.custom_fields["npn_submission_schema_version"]).to eq(1)
      expect(topic.custom_fields["npn_submission_type"]).to eq("image_critique")
      expect(topic.custom_fields["npn_critique_style"]).to eq("standard")
    end

    it "is a no-op on a blank topic" do
      expect { described_class.save(nil, { "a" => 1 }) }.not_to raise_error
    end

    it "is a no-op on empty metadata" do
      expect { described_class.save(topic, {}) }.not_to raise_error
      expect(topic.reload.custom_fields["npn_submission_type"]).to be_nil
    end

    it "never raises when the underlying write fails — logs and returns" do
      allow(topic).to receive(:upsert_custom_fields).and_raise(StandardError.new("disk full"))
      expect { described_class.save(topic, { "npn_submission_type" => "image_critique" }) }.not_to(
        raise_error,
      )
    end
  end
end
