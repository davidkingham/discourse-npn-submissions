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
      meta = described_class.build(submission(submission_type: "image", critique_style: "standard"))

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
          critique_style: nil, # not a known value
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
        {
          id: 7,
          title: "  Quiet Geometry  ",
          dates: "\tMay 20–26\t",
          description: "x",
          url: "https://e.com/c",
        },
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

    # --- Original image references ------------------------------------------
    #
    # These are read by the upcoming `discourse-revised-critique-image` and
    # `discourse-npn-critique-reply` plugins. This plugin owns only the
    # originals; revisions live on a sibling plugin's keys.

    describe "original image-version metadata" do
      fab!(:second_upload) { Fabricate(:upload, user: user) }
      fab!(:third_upload) { Fabricate(:upload, user: user) }

      it "stores all five image keys for a single-image Image Critique" do
        meta = described_class.build(submission)

        expect(meta).to include(
          "npn_critique_image_version_schema" => 1,
          "npn_original_primary_image_upload_id" => upload.id,
          "npn_original_image_upload_ids" => [upload.id],
          "npn_original_image_count" => 1,
        )
        expect(meta["npn_original_primary_image_url"]).to be_present
        # URL is built from upload.url via Discourse.store.cdn_url. The exact
        # form depends on store/CDN config; the canonical filename always
        # ends up in the result.
        expect(meta["npn_original_primary_image_url"]).to include(File.basename(upload.url))
      end

      it "uses the first submitted image as the original primary in a multi-image submission" do
        sub =
          submission(
            data: {
              "feedback_focus" => "artistic",
              "images" => [
                { "upload_id" => upload.id, "note" => "" },
                { "upload_id" => second_upload.id, "note" => "" },
                { "upload_id" => third_upload.id, "note" => "" },
              ],
            },
          )

        meta = described_class.build(sub)

        expect(meta["npn_original_primary_image_upload_id"]).to eq(upload.id)
        expect(meta["npn_original_image_upload_ids"]).to eq(
          [upload.id, second_upload.id, third_upload.id],
        )
        expect(meta["npn_original_image_count"]).to eq(3)
      end

      it "preserves submission order in npn_original_image_upload_ids" do
        sub =
          submission(
            data: {
              "feedback_focus" => "artistic",
              "images" => [
                { "upload_id" => third_upload.id, "note" => "" },
                { "upload_id" => upload.id, "note" => "" },
                { "upload_id" => second_upload.id, "note" => "" },
              ],
            },
          )

        expect(described_class.build(sub)["npn_original_image_upload_ids"]).to eq(
          [third_upload.id, upload.id, second_upload.id],
        )
      end

      it "removes duplicate upload IDs while preserving the first occurrence" do
        # Submission#image_entries already dedupes, so duplicates in the raw
        # data never reach the metadata builder — but the contract on the
        # stored field is documented as "no duplicates", and this proves it
        # holds end-to-end even if a future change introduces duplicates
        # upstream.
        sub =
          submission(
            data: {
              "feedback_focus" => "artistic",
              "images" => [
                { "upload_id" => upload.id, "note" => "" },
                { "upload_id" => second_upload.id, "note" => "" },
                { "upload_id" => upload.id, "note" => "duplicate" },
                { "upload_id" => second_upload.id, "note" => "duplicate" },
              ],
            },
          )

        expect(described_class.build(sub)["npn_original_image_upload_ids"]).to eq(
          [upload.id, second_upload.id],
        )
        expect(described_class.build(sub)["npn_original_image_count"]).to eq(2)
      end

      it "stores image metadata for a Weekly Challenge submission" do
        allow(DiscourseNpnSubmissions::WeeklyChallengeInfo).to receive(:current).and_return(nil)
        meta = described_class.build(submission(submission_type: "weekly_challenge"))

        expect(meta["npn_critique_image_version_schema"]).to eq(1)
        expect(meta["npn_original_primary_image_upload_id"]).to eq(upload.id)
        expect(meta["npn_original_image_upload_ids"]).to eq([upload.id])
        expect(meta["npn_original_image_count"]).to eq(1)
      end

      it "stores image metadata for a Project Critique with images" do
        sub =
          submission(
            submission_type: "project",
            critique_style: nil,
            data: {
              "method" => "images",
              "feedback_focus" => "artistic",
              "images" => [
                { "upload_id" => upload.id, "note" => "" },
                { "upload_id" => second_upload.id, "note" => "" },
              ],
            },
          )

        meta = described_class.build(sub)

        expect(meta["npn_critique_image_version_schema"]).to eq(1)
        expect(meta["npn_original_primary_image_upload_id"]).to eq(upload.id)
        expect(meta["npn_original_image_upload_ids"]).to eq([upload.id, second_upload.id])
        expect(meta["npn_original_image_count"]).to eq(2)
      end

      it "omits image keys when no surviving uploads are referenced" do
        sub =
          DiscourseNpnSubmissions::Submission.new(
            user_id: user.id,
            submission_type: "image",
            status: "submitted",
            critique_style: "standard",
            title: "Imageless",
            data: {
              "feedback_focus" => "artistic",
            },
          )

        meta = described_class.build(sub)

        expect(meta.keys).not_to include(
          "npn_critique_image_version_schema",
          "npn_original_primary_image_upload_id",
          "npn_original_primary_image_url",
          "npn_original_image_upload_ids",
          "npn_original_image_count",
        )
        # The non-image metadata fields still go through.
        expect(meta).to include(
          "npn_submission_schema_version" => 1,
          "npn_submission_type" => "image_critique",
          "npn_feedback_focus" => "artistic_expressive",
        )
      end

      it "swallows a single image-extraction failure without losing the rest of the metadata" do
        # Mimic an unexpected error reading uploads (corrupted row, store
        # config quirk, etc.). The non-image metadata should still come
        # through, and a single warn_exception entry should be logged.
        allow(described_class).to receive(:original_uploads_for).and_raise(
          StandardError.new("boom"),
        )
        allow(Discourse).to receive(:warn_exception)

        meta = described_class.build(submission)

        expect(meta.keys).not_to include(
          "npn_original_primary_image_upload_id",
          "npn_original_image_upload_ids",
          "npn_original_image_count",
          "npn_critique_image_version_schema",
        )
        expect(meta).to include(
          "npn_submission_schema_version" => 1,
          "npn_submission_type" => "image_critique",
        )
        expect(Discourse).to have_received(:warn_exception).once
      end

      it "length-caps an over-long image URL" do
        # Simulate a pathologically long resolved URL (signed-storage edge
        # case). The stored value never exceeds the documented cap.
        long_url = "https://example.com/#{"a" * (described_class::MAX_IMAGE_URL + 100)}"
        allow(described_class).to receive(:stable_upload_url).and_return(long_url)

        meta = described_class.build(submission)

        expect(meta["npn_original_primary_image_url"].length).to be <=
          described_class::MAX_IMAGE_URL
      end
    end

    # --- Structured project payload -----------------------------------------
    #
    # Source of truth for the future project-revision plugin. The Project
    # Overview grid + Image Sequence in the post body are display output
    # derived from the same `image_entries`; downstream readers should
    # consult this custom field rather than parse cooked HTML.

    describe "project submission data" do
      fab!(:upload_a) { Fabricate(:upload, user: user) }
      fab!(:upload_b) { Fabricate(:upload, user: user) }
      fab!(:upload_c) { Fabricate(:upload, user: user) }

      def project_submission(images:, extra_data: {})
        DiscourseNpnSubmissions::Submission.new(
          user_id: user.id,
          submission_type: "project",
          status: "submitted",
          critique_style: nil,
          title: "My Project",
          data: { "method" => "images", "feedback_focus" => "artistic", "images" => images }.merge(
            extra_data,
          ),
        )
      end

      it "stores npn_project_submission_data for an images-method project" do
        meta =
          described_class.build(
            project_submission(images: [{ "upload_id" => upload_a.id, "note" => "" }]),
          )
        data = meta["npn_project_submission_data"]

        expect(data).to include("type" => "project_critique", "version" => 1)
        expect(data["images"].size).to eq(1)
        expect(data["images"][0]).to include(
          "position" => 1,
          "upload_id" => upload_a.id,
          "short_url" => upload_a.short_url,
          "caption" => "",
          "alt" => "Image 1",
        )
        # Opaque hex slot id, decoupled from position and upload.
        expect(data["images"][0]["id"]).to match(/\A[0-9a-f]{16}\z/)
      end

      it "preserves submission order in the images array" do
        meta =
          described_class.build(
            project_submission(
              images: [
                { "upload_id" => upload_c.id, "note" => "" },
                { "upload_id" => upload_a.id, "note" => "" },
                { "upload_id" => upload_b.id, "note" => "" },
              ],
            ),
          )

        upload_ids = meta["npn_project_submission_data"]["images"].map { |i| i["upload_id"] }
        positions = meta["npn_project_submission_data"]["images"].map { |i| i["position"] }
        alts = meta["npn_project_submission_data"]["images"].map { |i| i["alt"] }

        expect(upload_ids).to eq([upload_c.id, upload_a.id, upload_b.id])
        expect(positions).to eq([1, 2, 3])
        expect(alts).to eq(["Image 1", "Image 2", "Image 3"])
      end

      it "stores captions when present and an empty string when absent" do
        meta =
          described_class.build(
            project_submission(
              images: [
                { "upload_id" => upload_a.id, "note" => "Opening shot" },
                { "upload_id" => upload_b.id, "note" => "  " },
                { "upload_id" => upload_c.id }, # note key absent entirely
              ],
            ),
          )

        captions = meta["npn_project_submission_data"]["images"].map { |i| i["caption"] }
        expect(captions).to eq(["Opening shot", "", ""])
      end

      it "gives every image a unique stable id" do
        meta =
          described_class.build(
            project_submission(
              images: [
                { "upload_id" => upload_a.id, "note" => "" },
                { "upload_id" => upload_b.id, "note" => "" },
                { "upload_id" => upload_c.id, "note" => "" },
              ],
            ),
          )

        ids = meta["npn_project_submission_data"]["images"].map { |i| i["id"] }
        expect(ids.uniq.size).to eq(3)
        ids.each { |id| expect(id).to match(/\A[0-9a-f]{16}\z/) }
      end

      it "does not write the field for image-critique submissions" do
        meta = described_class.build(submission(submission_type: "image"))
        expect(meta.keys).not_to include("npn_project_submission_data")
      end

      it "does not write the field for weekly-challenge submissions" do
        allow(DiscourseNpnSubmissions::WeeklyChallengeInfo).to receive(:current).and_return(nil)
        meta = described_class.build(submission(submission_type: "weekly_challenge"))
        expect(meta.keys).not_to include("npn_project_submission_data")
      end

      it "does not write the field for PDF projects (no image array)" do
        pdf_upload = Fabricate(:upload, user: user)
        thumb = Fabricate(:upload, user: user)
        sub =
          DiscourseNpnSubmissions::Submission.new(
            user_id: user.id,
            submission_type: "project",
            status: "submitted",
            title: "PDF Project",
            data: {
              "method" => "pdf",
              "feedback_focus" => "both",
              "pdf_upload_id" => pdf_upload.id,
              "representative_image_upload_id" => thumb.id,
            },
          )

        expect(described_class.build(sub).keys).not_to include("npn_project_submission_data")
      end

      it "does not write the field for URL projects (no image array)" do
        thumb = Fabricate(:upload, user: user)
        sub =
          DiscourseNpnSubmissions::Submission.new(
            user_id: user.id,
            submission_type: "project",
            status: "submitted",
            title: "URL Project",
            data: {
              "method" => "url",
              "feedback_focus" => "both",
              "link_url" => "https://example.com",
              "representative_image_upload_id" => thumb.id,
            },
          )

        expect(described_class.build(sub).keys).not_to include("npn_project_submission_data")
      end

      it "swallows extraction errors without losing the rest of the metadata" do
        # An unexpected error inside add_project_submission_data! must not
        # blank the schema/type/focus fields that ran before it.
        allow(SecureRandom).to receive(:hex).and_raise(StandardError.new("boom"))
        allow(Discourse).to receive(:warn_exception)

        meta =
          described_class.build(
            project_submission(images: [{ "upload_id" => upload_a.id, "note" => "" }]),
          )

        expect(meta.keys).not_to include("npn_project_submission_data")
        expect(meta).to include(
          "npn_submission_schema_version" => 1,
          "npn_submission_type" => "project_critique",
        )
        expect(Discourse).to have_received(:warn_exception).at_least(:once)
      end
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

    it "round-trips original image metadata with correct types" do
      # End-to-end check that the plugin.rb registrations (:integer, :string,
      # :json) typecast on read so the critique reply plugin gets the right
      # Ruby types back — especially the array, which the legacy
      # array-of-string custom-field shape would have flattened.
      meta = {
        "npn_critique_image_version_schema" => 1,
        "npn_original_primary_image_upload_id" => 4242,
        "npn_original_primary_image_url" => "/uploads/default/original/1X/abc.jpg",
        "npn_original_image_upload_ids" => [4242, 4243, 4244],
        "npn_original_image_count" => 3,
      }

      described_class.save(topic, meta)
      topic.reload

      expect(topic.custom_fields["npn_critique_image_version_schema"]).to eq(1)
      expect(topic.custom_fields["npn_original_primary_image_upload_id"]).to eq(4242)
      expect(topic.custom_fields["npn_original_primary_image_url"]).to eq(
        "/uploads/default/original/1X/abc.jpg",
      )
      expect(topic.custom_fields["npn_original_image_upload_ids"]).to eq([4242, 4243, 4244])
      expect(topic.custom_fields["npn_original_image_count"]).to eq(3)
    end

    it "round-trips the nested project submission payload as a real Hash" do
      # Confirms the :json registration on PROJECT_SUBMISSION_DATA_KEY hands
      # back a real Hash (with a nested Array of Hashes) on read, not a
      # JSON-encoded string — that's the contract the project-revision
      # plugin will rely on.
      payload = {
        "type" => "project_critique",
        "version" => 1,
        "images" => [
          {
            "id" => "abcdef0123456789",
            "position" => 1,
            "upload_id" => 4242,
            "short_url" => "upload://abc.jpeg",
            "caption" => "First frame",
            "alt" => "Image 1",
          },
          {
            "id" => "fedcba9876543210",
            "position" => 2,
            "upload_id" => 4243,
            "short_url" => "upload://def.jpeg",
            "caption" => "",
            "alt" => "Image 2",
          },
        ],
      }

      described_class.save(topic, { "npn_project_submission_data" => payload })
      topic.reload

      stored = topic.custom_fields["npn_project_submission_data"]
      expect(stored).to be_a(Hash)
      expect(stored["type"]).to eq("project_critique")
      expect(stored["version"]).to eq(1)
      expect(stored["images"]).to be_an(Array)
      expect(stored["images"].size).to eq(2)
      expect(stored["images"][0]["upload_id"]).to eq(4242)
      expect(stored["images"][0]["caption"]).to eq("First frame")
      expect(stored["images"][1]["alt"]).to eq("Image 2")
    end
  end
end
