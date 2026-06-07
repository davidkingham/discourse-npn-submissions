# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnSubmissions::Submitter do
  fab!(:group)
  fab!(:user)
  fab!(:other_user, :user)
  fab!(:category)
  fab!(:upload) { Fabricate(:upload, user: user) }
  fab!(:extra_upload) { Fabricate(:upload, user: user) }
  fab!(:foreign_upload) { Fabricate(:upload, user: other_user) }
  fab!(:tag_landscape) { Fabricate(:tag, name: "landscape") }
  fab!(:tag_sunrise) { Fabricate(:tag, name: "sunrise") }

  before do
    SiteSetting.tagging_enabled = true
    SiteSetting.npn_submissions_enabled = true
    SiteSetting.npn_submissions_allowed_groups = group.id.to_s
    SiteSetting.npn_submissions_critique_category_id = category.id.to_s
    group.add(user)
  end

  def data(extra = {})
    {
      "feedback_focus" => "artistic",
      "main_upload_id" => upload.id,
      "additional_images" => [],
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

  describe "valid submission" do
    it "creates a normal topic owned by the user with the formatted body" do
      submission = described_class.call(user: user, attrs: attrs, tz_name: "America/Denver")

      expect(submission.status).to eq("submitted")
      expect(submission.topic_id).to be_present
      expect(submission.client_timezone).to eq("America/Denver")

      topic = Topic.find(submission.topic_id)
      expect(topic.user_id).to eq(user.id)
      expect(topic.category_id).to eq(category.id)

      raw = topic.first_post.raw
      expect(raw).to include("<strong>Critique Style:</strong> Standard")
      expect(raw).to include("<strong>Feedback Focus:</strong> Artistic / Expressive")
      expect(raw).to include("### Feedback Requested")
      expect(raw).to include(upload.short_url)
    end

    it "attaches normalized metadata to the created topic" do
      submission = described_class.call(user: user, attrs: attrs)
      topic = Topic.find(submission.topic_id)

      expect(topic.custom_fields["npn_submission_schema_version"]).to eq(1)
      expect(topic.custom_fields["npn_submission_type"]).to eq("image_critique")
      expect(topic.custom_fields["npn_critique_style"]).to eq("standard")
      expect(topic.custom_fields["npn_feedback_focus"]).to eq("artistic_expressive")
      # No weekly challenge identity fields for an image submission.
      expect(topic.custom_fields["npn_wordpress_challenge_id"]).to be_nil
      expect(topic.custom_fields["npn_weekly_challenge_title"]).to be_nil
    end

    it "still creates the topic when metadata saving fails" do
      allow(DiscourseNpnSubmissions::TopicMetadata).to receive(:save).and_raise(
        StandardError.new("metadata storage offline"),
      )

      # Submitter wraps the failure internally — the topic must still exist
      # and the submission must still be marked submitted.
      submission = described_class.call(user: user, attrs: attrs)
      expect(submission.status).to eq("submitted")
      expect(Topic.find(submission.topic_id)).to be_present
    end

    it "stores the main upload and additional images with notes" do
      SiteSetting.npn_submissions_max_single_images = 2
      submission =
        described_class.call(
          user: user,
          attrs:
            attrs(
              data:
                data(
                  "additional_images" => [
                    { "upload_id" => extra_upload.id, "note" => "Tighter crop" },
                  ],
                ),
            ),
        )

      uploads = submission.submission_uploads.order(:position)
      expect(uploads.map(&:role)).to eq(%w[main variation])
      expect(uploads.last.caption).to eq("Tighter crop")

      raw = Topic.find(submission.topic_id).first_post.raw
      expect(raw).to include(extra_upload.short_url)
      expect(raw).to include("*Tighter crop*")
    end
  end

  describe "submitting an existing draft" do
    it "submits the current form data, not a stale stored draft" do
      # Draft saved early, before an image was added (data.images is empty).
      draft =
        DiscourseNpnSubmissions::DraftStore.create(
          user,
          attrs(data: data("main_upload_id" => nil, "images" => [])),
        )
      expect(draft.image_entries.size).to eq(0)

      # The user then adds an image and submits; the form sends the full payload.
      submission =
        described_class.call(
          user: user,
          draft_id: draft.id,
          attrs: attrs(data: data("images" => [{ "upload_id" => upload.id, "note" => "" }])),
        )

      expect(submission.id).to eq(draft.id)
      expect(submission.status).to eq("submitted")
      expect(submission.image_entries.size).to eq(1)
    end
  end

  describe "authorization" do
    it "raises NotAllowed when the user cannot submit" do
      group.remove(user)
      expect { described_class.call(user: user, attrs: attrs) }.to raise_error(
        described_class::NotAllowed,
      )
    end
  end

  describe "validation boundary" do
    it "rejects a blank title" do
      expect { described_class.call(user: user, attrs: attrs(title: "  ")) }.to raise_error(
        described_class::InvalidSubmission,
      )
    end

    it "requires at least one image" do
      expect {
        described_class.call(user: user, attrs: attrs(data: data("main_upload_id" => nil)))
      }.to raise_error(described_class::InvalidSubmission, /at least one image/i)
    end

    it "rejects more images than the configured maximum" do
      SiteSetting.npn_submissions_max_single_images = 1
      expect {
        described_class.call(
          user: user,
          attrs:
            attrs(
              data:
                data(
                  "images" => [
                    { "upload_id" => upload.id, "note" => "" },
                    { "upload_id" => extra_upload.id, "note" => "" },
                  ],
                ),
            ),
        )
      }.to raise_error(described_class::InvalidSubmission, /at most 1 image/i)
    end

    it "accepts the unified images array up to the configured maximum" do
      SiteSetting.npn_submissions_max_single_images = 2
      submission =
        described_class.call(
          user: user,
          attrs:
            attrs(
              data:
                data(
                  "images" => [
                    { "upload_id" => upload.id, "note" => "" },
                    { "upload_id" => extra_upload.id, "note" => "Variation" },
                  ],
                ),
            ),
        )

      expect(submission.status).to eq("submitted")
      uploads = submission.submission_uploads.order(:position)
      expect(uploads.map(&:role)).to eq(%w[main variation])
    end

    it "requires a feedback focus" do
      expect {
        described_class.call(user: user, attrs: attrs(data: data("feedback_focus" => "")))
      }.to raise_error(described_class::InvalidSubmission, /feedback/i)
    end

    it "requires the standard feedback_requested field" do
      expect {
        described_class.call(user: user, attrs: attrs(data: data("fields" => {})))
      }.to raise_error(described_class::InvalidSubmission, /Feedback Requested is required/)
    end

    it "requires the feedback_requested field for in-depth (everything else is optional)" do
      # Empty fields hash: should fail on the only remaining required field.
      expect {
        described_class.call(
          user: user,
          attrs: attrs(critique_style: "in_depth", data: data("fields" => {})),
        )
      }.to raise_error(described_class::InvalidSubmission, /Feedback Requested is required/)

      # The simplified flow no longer requires Self-Critique, Creative
      # Direction, About This Image, or Why This Image. As long as the
      # final ask is present, an in-depth submission is valid.
      submission =
        described_class.call(
          user: user,
          attrs:
            attrs(
              critique_style: "in_depth",
              data: data("fields" => { "feedback_requested" => "Where to focus." }),
            ),
        )
      expect(submission.status).to eq("submitted")
    end

    it "requires questions for viewers for initial reaction" do
      expect {
        described_class.call(
          user: user,
          attrs: attrs(critique_style: "reaction", data: data("fields" => {})),
        )
      }.to raise_error(described_class::InvalidSubmission, /Questions for Viewers is required/)
    end

    it "requires technical details when the focus is technical" do
      expect {
        described_class.call(
          user: user,
          attrs:
            attrs(
              data:
                data("feedback_focus" => "technical", "fields" => { "feedback_requested" => "x" }),
            ),
        )
      }.to raise_error(described_class::InvalidSubmission, /Technical Details is required/)
    end

    it "accepts a metadata screenshot in place of technical details text" do
      submission =
        described_class.call(
          user: user,
          attrs:
            attrs(
              data:
                data(
                  "feedback_focus" => "technical",
                  "metadata_screenshot_upload_id" => extra_upload.id,
                  "fields" => {
                    "feedback_requested" => "x",
                  },
                ),
            ),
        )

      expect(submission.status).to eq("submitted")
      roles = submission.submission_uploads.pluck(:role)
      expect(roles).to include("metadata_screenshot")

      raw = Topic.find(submission.topic_id).first_post.raw
      expect(raw).to include("### Technical Details")
      expect(raw).to include("![Metadata screenshot](#{extra_upload.short_url})")
    end

    it "requires at least one descriptive tag" do
      expect {
        described_class.call(user: user, attrs: attrs(data: data("tags" => [])))
      }.to raise_error(described_class::InvalidSubmission, /tag/i)
    end

    it "rejects unknown tags and does not create them" do
      expect {
        described_class.call(
          user: user,
          attrs: attrs(data: data("tags" => %w[landscape brandnewtag])),
        )
      }.to raise_error(described_class::InvalidSubmission, /Unknown tags/)

      expect(Tag.where(name: "brandnewtag")).to be_empty
    end

    it "rejects an upload the submitting user does not own" do
      expect {
        described_class.call(
          user: user,
          attrs: attrs(data: data("main_upload_id" => foreign_upload.id)),
        )
      }.to raise_error(described_class::InvalidSubmission, /not available/)
    end

    it "accepts an upload reached via Discourse's SHA1 dedup (UserUpload link exists)" do
      # Real-world case: a regular allowed user uploads a fresh image whose
      # bytes happen to match an existing upload's sha1. Discourse returns the
      # existing Upload record (owned by another user) AND creates a UserUpload
      # row linking the current user — that's the "this user pushed these bytes
      # through /uploads.json" signal, and the guard must accept it.
      UserUpload.create!(upload_id: foreign_upload.id, user_id: user.id)

      submission =
        described_class.call(
          user: user,
          attrs: attrs(data: data("main_upload_id" => foreign_upload.id)),
        )

      expect(submission.status).to eq("submitted")
    end

    it "rejects submission when no target category is configured" do
      SiteSetting.npn_submissions_critique_category_id = ""
      expect { described_class.call(user: user, attrs: attrs) }.to raise_error(
        described_class::InvalidSubmission,
        /target category/,
      )
    end
  end

  describe "daily limit" do
    before { SiteSetting.npn_submissions_enforce_daily_limit = true }

    it "blocks submission and preserves the draft when the limit is exceeded" do
      DiscourseNpnSubmissions::Submission.create!(
        user_id: user.id,
        submission_type: "image",
        status: "submitted",
        submitted_at: Time.zone.now,
      )

      draft = DiscourseNpnSubmissions::DraftStore.create(user, attrs)

      expect { described_class.call(user: user, draft_id: draft.id) }.to raise_error(
        DiscourseNpnSubmissions::DailyLimit::Exceeded,
      )

      expect(draft.reload.status).to eq("draft")
    end
  end

  describe "topic creation failure" do
    it "marks the submission failed and stores the error message" do
      errors = ActiveModel::Errors.new(DiscourseNpnSubmissions::Submission.new)
      errors.add(:base, "boom")
      allow_any_instance_of(PostCreator).to receive(:create).and_return(nil)
      allow_any_instance_of(PostCreator).to receive(:errors).and_return(errors)

      draft = DiscourseNpnSubmissions::DraftStore.create(user, attrs)

      expect { described_class.call(user: user, draft_id: draft.id) }.to raise_error(
        described_class::CreationFailed,
      )

      draft.reload
      expect(draft.status).to eq("failed")
      expect(draft.error_message).to eq("boom")
    end
  end

  describe "weekly challenge" do
    fab!(:weekly_tag) { Fabricate(:tag, name: "weekly-challenge") }

    before { SiteSetting.npn_submissions_weekly_challenge_tag = "weekly-challenge" }

    it "applies the configured weekly challenge tag automatically on submit" do
      submission =
        described_class.call(user: user, attrs: attrs(submission_type: "weekly_challenge"))

      expect(submission.submission_type).to eq("weekly_challenge")
      names = Topic.find(submission.topic_id).tags.pluck(:name)
      expect(names).to include("weekly-challenge", "landscape", "sunrise")
    end

    it "still requires at least one user-selected descriptive tag" do
      expect {
        described_class.call(
          user: user,
          attrs: attrs(submission_type: "weekly_challenge", data: data("tags" => [])),
        )
      }.to raise_error(described_class::InvalidSubmission, /tag/i)
    end

    it "does not duplicate the weekly tag if the user already selected it" do
      submission =
        described_class.call(
          user: user,
          attrs:
            attrs(
              submission_type: "weekly_challenge",
              data: data("tags" => %w[landscape weekly-challenge]),
            ),
        )

      names = Topic.find(submission.topic_id).tags.pluck(:name)
      expect(names.count("weekly-challenge")).to eq(1)
    end

    it "does not add the weekly tag to image submissions" do
      submission = described_class.call(user: user, attrs: attrs)
      expect(Topic.find(submission.topic_id).tags.pluck(:name)).not_to include("weekly-challenge")
    end

    it "counts toward the same daily limit shared across submission types" do
      SiteSetting.npn_submissions_enforce_daily_limit = true
      described_class.call(user: user, attrs: attrs) # an image critique today

      expect {
        described_class.call(user: user, attrs: attrs(submission_type: "weekly_challenge"))
      }.to raise_error(DiscourseNpnSubmissions::DailyLimit::Exceeded)
    end

    it "attaches weekly-identity metadata (id/title/dates/url) to the created topic" do
      allow(DiscourseNpnSubmissions::WeeklyChallengeInfo).to receive(:current).and_return(
        {
          id: 1241,
          title: "Celebrating Biodiversity",
          dates: "5/24/26 - 5/30/26",
          description: "x",
          url: "https://www.naturephotographers.network/weekly-challenge/1241/",
        },
      )

      submission =
        described_class.call(user: user, attrs: attrs(submission_type: "weekly_challenge"))
      topic = Topic.find(submission.topic_id)

      expect(topic.custom_fields["npn_submission_type"]).to eq("weekly_challenge")
      expect(topic.custom_fields["npn_wordpress_challenge_id"]).to eq(1241)
      expect(topic.custom_fields["npn_weekly_challenge_title"]).to eq("Celebrating Biodiversity")
      expect(topic.custom_fields["npn_weekly_challenge_dates"]).to eq("5/24/26 - 5/30/26")
      expect(topic.custom_fields["npn_wordpress_challenge_url"]).to eq(
        "https://www.naturephotographers.network/weekly-challenge/1241/",
      )
    end

    it "includes the weekly tag in the preview's applied tags" do
      result =
        described_class.preview(user: user, attrs: attrs(submission_type: "weekly_challenge"))
      expect(result[:tags]).to include("weekly-challenge", "landscape", "sunrise")
    end

    it "includes the synced challenge title and dates in the submitted post" do
      allow(DiscourseNpnSubmissions::WeeklyChallengeInfo).to receive(:current).and_return(
        { title: "Quiet Geometry", dates: "May 20–26, 2026", description: nil, url: nil },
      )

      submission =
        described_class.call(user: user, attrs: attrs(submission_type: "weekly_challenge"))

      raw = Topic.find(submission.topic_id).first_post.raw
      expect(raw).to include('<div class="npn-weekly-challenge-title">Quiet Geometry</div>')
      expect(raw).to include('<div class="npn-weekly-challenge-dates">May 20–26, 2026</div>')
    end

    it "still submits successfully when the WordPress sync is unavailable" do
      allow(DiscourseNpnSubmissions::WeeklyChallengeInfo).to receive(:current).and_return(nil)

      submission =
        described_class.call(user: user, attrs: attrs(submission_type: "weekly_challenge"))

      expect(submission.status).to eq("submitted")
      expect(Topic.find(submission.topic_id).first_post.raw).not_to include(
        "npn-weekly-challenge-context",
      )
    end

    it "uses the same challenge title for the preview and the submitted post" do
      allow(DiscourseNpnSubmissions::WeeklyChallengeInfo).to receive(:current).and_return(
        { title: "Quiet Geometry", dates: "May 20–26, 2026", description: nil, url: nil },
      )

      preview =
        described_class.preview(user: user, attrs: attrs(submission_type: "weekly_challenge"))
      submission =
        described_class.call(user: user, attrs: attrs(submission_type: "weekly_challenge"))
      raw = Topic.find(submission.topic_id).first_post.raw

      title_div = '<div class="npn-weekly-challenge-title">Quiet Geometry</div>'
      expect(preview[:markdown]).to include(title_div)
      expect(raw).to include(title_div)
    end
  end

  describe "project submissions" do
    fab!(:project_tag) { Fabricate(:tag, name: "project") }

    before do
      SiteSetting.npn_submissions_project_category_id = category.id.to_s
      SiteSetting.npn_submissions_project_tag = "project"
    end

    def project_data(extra = {})
      {
        "method" => "images",
        "feedback_focus" => "artistic",
        "images" => [{ "upload_id" => upload.id }, { "upload_id" => extra_upload.id }],
        "tags" => %w[landscape],
        "fields" => {
          "project_description" => "A cohesive body of work.",
          "self_critique" => "Working and improving.",
          "creative_direction" => "Quiet mood.",
          "feedback_requested" => "Does it cohere?",
          "project_intent" => "gallery",
        },
      }.merge(extra)
    end

    def project_attrs(overrides = {})
      {
        submission_type: "project",
        title: "My Landscape Project for Critique",
        data: project_data,
      }.merge(overrides)
    end

    it "submits an uploaded-images project and auto-applies the project tag" do
      submission = described_class.call(user: user, attrs: project_attrs)

      expect(submission.status).to eq("submitted")
      expect(submission.submission_type).to eq("project")
      topic = Topic.find(submission.topic_id)
      expect(topic.category_id).to eq(category.id)
      expect(topic.tags.pluck(:name)).to include("project", "landscape")
    end

    it "attaches metadata to a project topic (schema, type, focus; no critique style)" do
      submission = described_class.call(user: user, attrs: project_attrs)
      topic = Topic.find(submission.topic_id)

      expect(topic.custom_fields["npn_submission_schema_version"]).to eq(1)
      expect(topic.custom_fields["npn_submission_type"]).to eq("project_critique")
      expect(topic.custom_fields["npn_feedback_focus"]).to eq("artistic_expressive")
      expect(topic.custom_fields["npn_critique_style"]).to be_nil
    end

    it "allows fewer than the recommended minimum (warn, not block)" do
      submission =
        described_class.call(
          user: user,
          attrs: project_attrs(data: project_data("images" => [{ "upload_id" => upload.id }])),
        )
      expect(submission.status).to eq("submitted")
    end

    it "carries an optional per-image note through to the submitted post" do
      submission =
        described_class.call(
          user: user,
          attrs:
            project_attrs(
              data:
                project_data("images" => [{ "upload_id" => upload.id, "note" => "Opening frame" }]),
            ),
        )

      raw = Topic.find(submission.topic_id).first_post.raw
      expect(raw).to include("*Opening frame*")
    end

    it "preserves main image order via upload positions" do
      submission =
        described_class.call(
          user: user,
          attrs:
            project_attrs(
              data:
                project_data(
                  "images" => [{ "upload_id" => extra_upload.id }, { "upload_id" => upload.id }],
                ),
            ),
        )
      positions = submission.submission_uploads.where(role: "project_image").order(:position)
      expect(positions.pluck(:upload_id)).to eq([extra_upload.id, upload.id])
    end

    it "requires at least one user-selected descriptive tag" do
      expect {
        described_class.call(user: user, attrs: project_attrs(data: project_data("tags" => [])))
      }.to raise_error(described_class::InvalidSubmission, /tag/i)
    end

    it "does not duplicate the project tag if the user already selected it" do
      submission =
        described_class.call(
          user: user,
          attrs: project_attrs(data: project_data("tags" => %w[landscape project])),
        )
      names = Topic.find(submission.topic_id).tags.pluck(:name)
      expect(names.count("project")).to eq(1)
    end

    it "keeps alternates (optional) and stores them with the alternate role" do
      alt = Fabricate(:upload, user: user)
      submission =
        described_class.call(
          user: user,
          attrs: project_attrs(data: project_data("alternates" => [{ "upload_id" => alt.id }])),
        )
      alternates = submission.submission_uploads.where(role: "alternate")
      expect(alternates.pluck(:upload_id)).to eq([alt.id])
    end

    it "drops an alternate that duplicates a project image" do
      # `upload` is already a project image in project_data; adding it as an
      # alternate must be ignored so the same file isn't stored or shown twice.
      submission =
        described_class.call(
          user: user,
          attrs: project_attrs(data: project_data("alternates" => [{ "upload_id" => upload.id }])),
        )

      expect(submission.submission_uploads.where(role: "alternate")).to be_empty
      raw = Topic.find(submission.topic_id).first_post.raw
      expect(raw.scan(upload.short_url).size).to eq(1)
    end

    it "requires a PDF for the pdf method" do
      expect {
        described_class.call(
          user: user,
          attrs: project_attrs(data: project_data("method" => "pdf", "images" => [])),
        )
      }.to raise_error(described_class::InvalidSubmission, /PDF/i)
    end

    it "requires a representative image for the pdf method" do
      pdf = Fabricate(:upload, user: user)
      expect {
        described_class.call(
          user: user,
          attrs:
            project_attrs(
              data: project_data("method" => "pdf", "images" => [], "pdf_upload_id" => pdf.id),
            ),
        )
      }.to raise_error(described_class::InvalidSubmission, /representative image/i)
    end

    it "submits a pdf project with a representative image" do
      pdf = Fabricate(:upload, user: user)
      rep = Fabricate(:upload, user: user)
      submission =
        described_class.call(
          user: user,
          attrs:
            project_attrs(
              data:
                project_data(
                  "method" => "pdf",
                  "images" => [],
                  "pdf_upload_id" => pdf.id,
                  "representative_image_upload_id" => rep.id,
                ),
            ),
        )
      expect(submission.status).to eq("submitted")
      expect(submission.submission_uploads.where(role: "pdf").pluck(:upload_id)).to eq([pdf.id])
      expect(
        submission.submission_uploads.where(role: "representative_image").pluck(:upload_id),
      ).to eq([rep.id])
    end

    it "requires a valid URL for the url method" do
      rep = Fabricate(:upload, user: user)
      expect {
        described_class.call(
          user: user,
          attrs:
            project_attrs(
              data:
                project_data(
                  "method" => "url",
                  "images" => [],
                  "link_url" => "not a url",
                  "representative_image_upload_id" => rep.id,
                ),
            ),
        )
      }.to raise_error(described_class::InvalidSubmission, /URL/i)
    end

    it "requires a representative image for the url method" do
      expect {
        described_class.call(
          user: user,
          attrs:
            project_attrs(
              data:
                project_data(
                  "method" => "url",
                  "images" => [],
                  "link_url" => "https://example.com/p",
                ),
            ),
        )
      }.to raise_error(described_class::InvalidSubmission, /representative image/i)
    end

    it "submits a url project with a representative image" do
      rep = Fabricate(:upload, user: user)
      submission =
        described_class.call(
          user: user,
          attrs:
            project_attrs(
              data:
                project_data(
                  "method" => "url",
                  "images" => [],
                  "link_url" => "https://example.com/p",
                  "representative_image_upload_id" => rep.id,
                ),
            ),
        )
      expect(submission.status).to eq("submitted")
    end

    it "requires a submission method" do
      expect {
        described_class.call(user: user, attrs: project_attrs(data: project_data("method" => "")))
      }.to raise_error(described_class::InvalidSubmission, /how you/i)
    end

    it "requires a project feedback focus" do
      expect {
        described_class.call(
          user: user,
          attrs: project_attrs(data: project_data("feedback_focus" => "")),
        )
      }.to raise_error(described_class::InvalidSubmission, /feedback/i)
    end

    it "requires the project description" do
      expect {
        described_class.call(
          user: user,
          attrs:
            project_attrs(
              data: project_data("fields" => project_data["fields"].except("project_description")),
            ),
        )
      }.to raise_error(described_class::InvalidSubmission, /Brief Project Description/i)
    end

    it "requires the presentation goal (project intent)" do
      expect {
        described_class.call(
          user: user,
          attrs:
            project_attrs(
              data: project_data("fields" => project_data["fields"].except("project_intent")),
            ),
        )
      }.to raise_error(described_class::InvalidSubmission, /Presentation Goal/i)
    end

    it "counts toward the shared daily limit across submission types" do
      SiteSetting.npn_submissions_enforce_daily_limit = true
      described_class.call(user: user, attrs: attrs) # an image critique today

      expect { described_class.call(user: user, attrs: project_attrs) }.to raise_error(
        DiscourseNpnSubmissions::DailyLimit::Exceeded,
      )
    end
  end

  describe "descriptive tag group constraint" do
    fab!(:tag_group) { Fabricate(:tag_group, name: "critique-subjects") }

    before do
      tag_group.tags = [tag_landscape, tag_sunrise]
      SiteSetting.npn_submissions_descriptive_tag_group = "critique-subjects"
    end

    it "accepts tags that belong to the configured group" do
      submission =
        described_class.call(user: user, attrs: attrs(data: data("tags" => %w[landscape])))
      expect(submission.status).to eq("submitted")
    end

    it "rejects tags outside the configured group" do
      Fabricate(:tag, name: "macro")
      expect {
        described_class.call(user: user, attrs: attrs(data: data("tags" => %w[macro])))
      }.to raise_error(described_class::InvalidSubmission, /aren't allowed/i)
    end
  end

  describe ".preview" do
    it "builds the post markdown without creating a draft or topic" do
      result = nil
      expect { result = described_class.preview(user: user, attrs: attrs) }.not_to change {
        [DiscourseNpnSubmissions::Submission.count, Topic.count]
      }

      expect(result[:markdown]).to include("### Feedback Requested")
      expect(result[:markdown]).to include(upload.short_url)
    end

    it "runs the same content validation as submit" do
      expect {
        described_class.preview(user: user, attrs: attrs(data: data("tags" => [])))
      }.to raise_error(described_class::InvalidSubmission, /tag/i)
    end

    it "does not enforce the daily limit" do
      SiteSetting.npn_submissions_enforce_daily_limit = true
      DiscourseNpnSubmissions::Submission.create!(
        user_id: user.id,
        submission_type: "image",
        status: "submitted",
        submitted_at: Time.zone.now,
      )

      expect { described_class.preview(user: user, attrs: attrs) }.not_to raise_error
    end

    it "raises NotAllowed when the user cannot submit" do
      group.remove(user)
      expect { described_class.preview(user: user, attrs: attrs) }.to raise_error(
        described_class::NotAllowed,
      )
    end
  end

  describe "introduction submissions" do
    fab!(:intro_category, :category)

    before { SiteSetting.npn_submissions_introduction_category_id = intro_category.id.to_s }

    def intro_data(extra = {})
      { "images" => [], "fields" => { "about" => "I make quiet landscape photos.", "learning" => "" } }
        .merge(extra)
    end

    def intro_attrs(overrides = {})
      {
        submission_type: "introduction",
        critique_style: nil,
        title: "Hello from Colorado",
        data: intro_data,
      }.merge(overrides)
    end

    it "creates a topic in the configured introduction category with the formatted body" do
      submission = described_class.call(user: user, attrs: intro_attrs)
      topic = Topic.find(submission.topic_id)

      expect(submission.status).to eq("submitted")
      expect(submission.submission_type).to eq("introduction")
      expect(topic.category_id).to eq(intro_category.id)

      raw = topic.first_post.raw
      expect(raw).to include("### About Me")
      expect(raw).to include("I make quiet landscape photos.")
      # No critique scaffolding leaks into an introduction post.
      expect(raw).not_to include("npn-critique-guidance")
      expect(raw).not_to include("Feedback Requested")
      expect(raw).not_to include("Technical Details")
      expect(raw).not_to include("npn-project-submission")
    end

    it "renders the optional learning section when supplied, omits it when blank" do
      with_learning =
        described_class.preview(
          user: user,
          attrs:
            intro_attrs(
              data:
                intro_data(
                  "fields" => { "about" => "Hi.", "learning" => "Hoping to grow as a printer." },
                ),
            ),
        )
      expect(with_learning[:markdown]).to include("### What I’m Hoping to Learn or Explore")
      expect(with_learning[:markdown]).to include("Hoping to grow as a printer.")

      without_learning = described_class.preview(user: user, attrs: intro_attrs)
      expect(without_learning[:markdown]).not_to include("What I’m Hoping to Learn or Explore")
    end

    it "stores the optional image as a Markdown image at the top of the post" do
      submission =
        described_class.call(
          user: user,
          attrs: intro_attrs(data: intro_data("images" => [{ "upload_id" => upload.id }])),
        )
      raw = Topic.find(submission.topic_id).first_post.raw

      expect(raw).to match(/\A!\[Hello from Colorado\]\(upload:/)
    end

    it "rejects more than one image (introductions are single-image)" do
      expect {
        described_class.call(
          user: user,
          attrs:
            intro_attrs(
              data:
                intro_data(
                  "images" => [
                    { "upload_id" => upload.id },
                    { "upload_id" => extra_upload.id },
                  ],
                ),
            ),
        )
      }.to raise_error(described_class::InvalidSubmission, /at most one image/i)
    end

    it "requires the About You field" do
      expect {
        described_class.call(
          user: user,
          attrs: intro_attrs(data: intro_data("fields" => { "about" => "  " })),
        )
      }.to raise_error(described_class::InvalidSubmission, /About You is required/i)
    end

    it "does not require any descriptive tags" do
      submission =
        described_class.call(
          user: user,
          attrs: intro_attrs(data: intro_data("tags" => [])),
        )
      topic = Topic.find(submission.topic_id)

      expect(submission.status).to eq("submitted")
      # No descriptive tag, no auto-applied tag, no project/weekly tag.
      expect(topic.tags).to be_empty
    end

    it "does not count toward the critique daily limit and is not blocked by an existing critique" do
      # A critique submission first — that would normally exhaust the daily slot.
      described_class.call(user: user, attrs: attrs)

      # Introduction goes through cleanly afterward.
      expect {
        described_class.call(user: user, attrs: intro_attrs)
      }.not_to raise_error
    end

    it "still lets the user submit a critique even after submitting an introduction the same day" do
      described_class.call(user: user, attrs: intro_attrs)

      expect { described_class.call(user: user, attrs: attrs) }.not_to raise_error
    end

    it "fails clearly when the introduction category is not configured" do
      SiteSetting.npn_submissions_introduction_category_id = ""
      expect {
        described_class.call(user: user, attrs: intro_attrs)
      }.to raise_error(described_class::InvalidSubmission, /target category/i)
    end

    it "writes only the minimal topic-metadata fields for an introduction" do
      submission = described_class.call(user: user, attrs: intro_attrs)
      topic = Topic.find(submission.topic_id)

      expect(topic.custom_fields["npn_submission_type"]).to eq("introduction")
      expect(topic.custom_fields["npn_submission_schema_version"]).to eq(1)
      # No critique-style / feedback-focus / weekly fields for an intro.
      expect(topic.custom_fields.keys).not_to include(
        "npn_critique_style",
        "npn_feedback_focus",
        "npn_wordpress_challenge_id",
        "npn_weekly_challenge_title",
        "npn_critique_image_version_schema",
        "npn_original_primary_image_upload_id",
        "npn_original_primary_image_url",
        "npn_original_image_upload_ids",
        "npn_original_image_count",
        "npn_project_submission_data",
      )
    end

    it "previews the introduction body with no critique scaffolding" do
      preview = described_class.preview(user: user, attrs: intro_attrs)
      expect(preview[:markdown]).to include("### About Me")
      expect(preview[:tags]).to eq([])
    end
  end

  describe "new_member_image submissions" do
    fab!(:nmi_category, :category)

    before { SiteSetting.npn_submissions_new_member_image_category_id = nmi_category.id.to_s }

    def nmi_data(extra = {})
      {
        "images" => [{ "upload_id" => upload.id }],
        "fields" => { "about_this_image" => "", "feedback" => "" },
      }.merge(extra)
    end

    def nmi_attrs(overrides = {})
      {
        submission_type: "new_member_image",
        critique_style: nil,
        title: "Quiet coastal morning",
        data: nmi_data,
      }.merge(overrides)
    end

    it "creates a topic in the configured category with image, no critique scaffolding" do
      submission = described_class.call(user: user, attrs: nmi_attrs)
      topic = Topic.find(submission.topic_id)

      expect(submission.status).to eq("submitted")
      expect(submission.submission_type).to eq("new_member_image")
      expect(topic.category_id).to eq(nmi_category.id)

      raw = topic.first_post.raw
      expect(raw).to match(/\A!\[Quiet coastal morning\]\(upload:/)
      expect(raw).not_to include("npn-critique-guidance")
      expect(raw).not_to include("Feedback Requested")
      expect(raw).not_to include("Technical Details")
      expect(raw).not_to include("npn-project-submission")
      expect(raw).not_to include("About Me") # not the introduction layout
    end

    it "renders About This Image and Feedback Welcome only when provided" do
      with_both =
        described_class.preview(
          user: user,
          attrs:
            nmi_attrs(
              data:
                nmi_data(
                  "fields" => {
                    "about_this_image" => "Taken at sunrise.",
                    "feedback" => "Curious about the framing.",
                  },
                ),
            ),
        )
      expect(with_both[:markdown]).to include("### About This Image\n\nTaken at sunrise.")
      expect(with_both[:markdown]).to include(
        "### Feedback Welcome\n\nCurious about the framing.",
      )

      image_only = described_class.preview(user: user, attrs: nmi_attrs)
      expect(image_only[:markdown]).not_to include("About This Image")
      expect(image_only[:markdown]).not_to include("Feedback Welcome")
    end

    it "requires an image" do
      expect {
        described_class.call(
          user: user,
          attrs: nmi_attrs(data: nmi_data("images" => [])),
        )
      }.to raise_error(described_class::InvalidSubmission, /image is required/i)
    end

    it "rejects more than one image" do
      expect {
        described_class.call(
          user: user,
          attrs:
            nmi_attrs(
              data:
                nmi_data(
                  "images" => [
                    { "upload_id" => upload.id },
                    { "upload_id" => extra_upload.id },
                  ],
                ),
            ),
        )
      }.to raise_error(described_class::InvalidSubmission, /only one image/i)
    end

    it "rejects an upload owned by another user" do
      expect {
        described_class.call(
          user: user,
          attrs: nmi_attrs(data: nmi_data("images" => [{ "upload_id" => foreign_upload.id }])),
        )
      }.to raise_error(described_class::InvalidSubmission, /not available to you/i)
    end

    it "requires a title" do
      expect {
        described_class.call(user: user, attrs: nmi_attrs(title: "  "))
      }.to raise_error(described_class::InvalidSubmission, /title is required/i)
    end

    it "does not require any descriptive tags" do
      submission = described_class.call(user: user, attrs: nmi_attrs)
      topic = Topic.find(submission.topic_id)

      expect(submission.status).to eq("submitted")
      expect(topic.tags).to be_empty
    end

    it "does not count toward the critique daily limit (critique then NMI both succeed)" do
      described_class.call(user: user, attrs: attrs)
      expect { described_class.call(user: user, attrs: nmi_attrs) }.not_to raise_error
    end

    it "still lets the user submit a critique after a NMI submission the same day" do
      described_class.call(user: user, attrs: nmi_attrs)
      expect { described_class.call(user: user, attrs: attrs) }.not_to raise_error
    end

    it "fails clearly when the new-member-image category is not configured" do
      SiteSetting.npn_submissions_new_member_image_category_id = ""
      expect {
        described_class.call(user: user, attrs: nmi_attrs)
      }.to raise_error(described_class::InvalidSubmission, /target category/i)
    end

    it "writes only the minimal topic-metadata fields (no image-version refs)" do
      submission = described_class.call(user: user, attrs: nmi_attrs)
      topic = Topic.find(submission.topic_id)

      expect(topic.custom_fields["npn_submission_type"]).to eq("new_member_image")
      expect(topic.custom_fields["npn_submission_schema_version"]).to eq(1)
      expect(topic.custom_fields.keys).not_to include(
        "npn_critique_style",
        "npn_feedback_focus",
        "npn_wordpress_challenge_id",
        "npn_weekly_challenge_title",
        "npn_critique_image_version_schema",
        "npn_original_primary_image_upload_id",
        "npn_original_primary_image_url",
        "npn_original_image_upload_ids",
        "npn_original_image_count",
        "npn_project_submission_data",
      )
    end
  end
end
