# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnSubmissions::Editor do
  fab!(:group)
  fab!(:user) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:other_user) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:moderator)
  fab!(:category)
  fab!(:upload) { Fabricate(:upload, user: user) }
  fab!(:new_upload) { Fabricate(:upload, user: user) }
  fab!(:tag_landscape) { Fabricate(:tag, name: "landscape") }
  fab!(:tag_sunrise) { Fabricate(:tag, name: "sunrise") }
  fab!(:tag_forest) { Fabricate(:tag, name: "forest") }

  before do
    SiteSetting.tagging_enabled = true
    SiteSetting.npn_submissions_enabled = true
    SiteSetting.npn_submissions_allowed_groups = group.id.to_s
    SiteSetting.npn_submissions_critique_category_id = category.id.to_s
    group.add(user)
    group.add(other_user)
  end

  def data(extra = {})
    {
      "feedback_focus" => "artistic",
      "images" => [{ "upload_id" => upload.id, "note" => "" }],
      "tags" => %w[landscape sunrise],
      "fields" => {
        "feedback_requested" => "Does the composition feel balanced?",
      },
    }.merge(extra)
  end

  def attrs(overrides = {})
    {
      submission_type: "image",
      critique_style: "standard",
      title: "Please critique my landscape",
      data: data,
    }.merge(overrides)
  end

  def submit!(**overrides)
    DiscourseNpnSubmissions::Submitter.call(user: user, attrs: attrs(overrides))
  end

  def edit!(submission, editor: user, force: false, **overrides)
    described_class.call(
      user: editor,
      submission_id: submission.id,
      attrs: attrs(overrides),
      force: force,
    )
  end

  def first_post(submission)
    Post.find_by(topic_id: submission.topic_id, post_number: 1)
  end

  it "rebuilds the first post from the new form state and records a revision" do
    SiteSetting.editing_grace_period = 0
    submission = submit!
    edit!(
      submission,
      title: "Please critique my forest scene",
      data:
        data(
          "fields" => {
            "feedback_requested" => "Is the light too flat?",
          },
          "tags" => %w[forest],
        ),
    )

    post = first_post(submission)
    expect(post.raw).to include("Is the light too flat?")
    expect(post.raw).not_to include("Does the composition feel balanced?")
    expect(post.version).to eq(2)
    expect(post.topic.title).to eq("Please critique my forest scene")
    expect(post.topic.tags.pluck(:name)).to contain_exactly("forest")

    submission.reload
    expect(submission.title).to eq("Please critique my forest scene")
    expect(submission.field("feedback_requested")).to eq("Is the light too flat?")
    expect(submission.status).to eq("submitted")
  end

  it "keeps tags staff added by hand" do
    submission = submit!
    staff_tag = Fabricate(:tag, name: "featured")
    topic = Topic.find(submission.topic_id)
    DiscourseTagging.tag_topic_by_names(
      topic,
      Guardian.new(Discourse.system_user),
      %w[landscape sunrise featured],
    )

    edit!(submission, data: data("tags" => %w[forest]))

    expect(topic.reload.tags.pluck(:name)).to contain_exactly("forest", staff_tag.name)
  end

  it "lets the author swap images before anyone has replied" do
    submission = submit!
    edit!(submission, data: data("images" => [{ "upload_id" => new_upload.id, "note" => "" }]))

    post = first_post(submission)
    expect(post.raw).to include(new_upload.short_url)
    expect(post.raw).not_to include(upload.short_url)
    expect(submission.reload.submission_uploads.pluck(:upload_id)).to eq([new_upload.id])
    expect(post.topic.custom_fields["npn_original_primary_image_upload_id"]).to eq(new_upload.id)
  end

  context "after someone else has replied" do
    let!(:submission) { submit! }

    before { Fabricate(:post, topic: Topic.find(submission.topic_id), user: other_user) }

    it "refuses an image change" do
      expect {
        edit!(submission, data: data("images" => [{ "upload_id" => new_upload.id, "note" => "" }]))
      }.to raise_error(described_class::ImagesLocked)
      expect(first_post(submission).raw).to include(upload.short_url)
    end

    it "still allows text edits" do
      edit!(submission, data: data("fields" => { "feedback_requested" => "New question?" }))
      expect(first_post(submission).raw).to include("New question?")
    end

    it "reports images as locked" do
      state = described_class.state(user: user, submission_id: submission.id)
      expect(state[:images_locked]).to eq(true)
    end
  end

  it "does not lock images for the author's own replies" do
    submission = submit!
    Fabricate(:post, topic: Topic.find(submission.topic_id), user: user)
    state = described_class.state(user: user, submission_id: submission.id)
    expect(state[:images_locked]).to eq(false)
  end

  describe "posts changed outside the form" do
    it "is clean right after submit and after a form edit" do
      submission = submit!
      expect(
        described_class.state(user: user, submission_id: submission.id)[:edited_outside_form],
      ).to eq(false)

      edit!(submission, data: data("fields" => { "feedback_requested" => "Edited?" }))
      expect(
        described_class.state(user: user, submission_id: submission.id)[:edited_outside_form],
      ).to eq(false)
    end

    it "treats an older, never-revised post as clean even if the builder output changed" do
      submission = submit!
      post = first_post(submission)
      # As if the post predates the fingerprint and an older post builder
      # wrote different alt text.
      submission.update!(data: submission.data.except(described_class::POSTED_BODY_KEY))
      post.update_columns(raw: post.raw.sub("Original - ", "Old alt - "))

      expect(
        described_class.state(user: user, submission_id: submission.id)[:edited_outside_form],
      ).to eq(false)

      post.update_columns(version: 2)
      expect(
        described_class.state(user: user, submission_id: submission.id)[:edited_outside_form],
      ).to eq(true)
    end

    it "refuses to overwrite a manual edit unless forced" do
      submission = submit!
      post = first_post(submission)
      post.revise(user, raw: "#{post.raw}\n\nAdded by hand.")

      expect(
        described_class.state(user: user, submission_id: submission.id)[:edited_outside_form],
      ).to eq(true)
      expect { edit!(submission) }.to raise_error(described_class::EditedOutsideForm)

      edit!(submission, force: true)
      expect(post.reload.raw).not_to include("Added by hand.")
    end
  end

  it "keeps a revised-version block at the top of the post" do
    submission = submit!
    post = first_post(submission)
    block = <<~MD.strip
      <!-- revised-critique-image:begin -->
      ## Revised Version

      ![Revision 1 - a.jpg](#{new_upload.short_url})

      ---
      <!-- revised-critique-image:end -->

      ## Original Version
    MD
    post.revise(user, raw: "#{block}\n\n#{post.raw}")

    expect(
      described_class.state(user: user, submission_id: submission.id)[:edited_outside_form],
    ).to eq(false)

    edit!(submission, data: data("fields" => { "feedback_requested" => "After revision?" }))

    raw = post.reload.raw
    expect(raw).to start_with(block)
    expect(raw.scan("revised-critique-image:begin").size).to eq(1)
    expect(raw).to include("After revision?")
  end

  describe "weekly challenge" do
    fab!(:weekly_tag) { Fabricate(:tag, name: "weekly-challenge") }

    before { SiteSetting.npn_submissions_weekly_challenge_tag = "weekly-challenge" }

    it "keeps the challenge the post was published under" do
      allow(DiscourseNpnSubmissions::WeeklyChallengeInfo).to receive(:current).and_return(
        { id: 1, title: "Quiet Geometry", dates: "May 20–26", url: nil },
      )
      submission = submit!(submission_type: "weekly_challenge")

      allow(DiscourseNpnSubmissions::WeeklyChallengeInfo).to receive(:current).and_return(
        { id: 2, title: "Next Week", dates: "May 27–Jun 2", url: nil },
      )
      edit!(
        submission,
        submission_type: "weekly_challenge",
        data: data("fields" => { "feedback_requested" => "Edited?" }),
      )

      post = first_post(submission)
      expect(post.raw).to include("Quiet Geometry")
      expect(post.raw).not_to include("Next Week")
      expect(post.topic.custom_fields["npn_weekly_challenge_title"]).to eq("Quiet Geometry")
      expect(post.topic.tags.pluck(:name)).to include("weekly-challenge")
    end
  end

  describe "permissions" do
    it "does not let another member edit" do
      submission = submit!
      expect { edit!(submission, editor: other_user) }.to raise_error(described_class::NotAllowed)
    end

    it "lets staff edit" do
      submission = submit!
      edit!(
        submission,
        editor: moderator,
        data: data("fields" => { "feedback_requested" => "Mod fix" }),
      )
      expect(first_post(submission).raw).to include("Mod fix")
    end

    it "respects Discourse's edit time limit" do
      submission = submit!
      SiteSetting.post_edit_time_limit = 1
      first_post(submission).update_columns(created_at: 2.hours.ago)
      expect(described_class.editable_by?(user, submission)).to eq(false)
      expect { edit!(submission) }.to raise_error(described_class::NotAllowed)
    end

    it "ignores drafts" do
      draft = DiscourseNpnSubmissions::DraftStore.create(user, attrs)
      expect { edit!(draft) }.to raise_error(described_class::NotFound)
    end

    it "refuses types without a form edit mode" do
      submission = submit!
      submission.update_columns(submission_type: "help")
      expect { edit!(submission) }.to raise_error(described_class::NotEditable)
    end
  end

  it "validates like a new submission" do
    submission = submit!
    expect { edit!(submission, title: "") }.to raise_error(
      DiscourseNpnSubmissions::Submitter::InvalidSubmission,
    )
  end
end
