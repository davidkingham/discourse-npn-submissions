# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnSubmissions::PostBuilder do
  fab!(:user)
  fab!(:main) { Fabricate(:upload, user: user) }
  fab!(:variation) { Fabricate(:upload, user: user) }
  fab!(:meta) { Fabricate(:upload, user: user) }

  def submission(
    critique_style:,
    feedback_focus: "artistic",
    fields: {},
    additional: [],
    metadata: nil
  )
    DiscourseNpnSubmissions::Submission.new(
      user_id: user.id,
      submission_type: "image",
      status: "draft",
      critique_style: critique_style,
      title: "My Image",
      data: {
        "feedback_focus" => feedback_focus,
        "main_upload_id" => main.id,
        "additional_images" => additional,
        "metadata_screenshot_upload_id" => metadata&.id,
        "fields" => fields,
      },
    )
  end

  it "renders the standard layout and omits blank sections" do
    raw =
      described_class.build(
        submission(critique_style: "standard", fields: { "feedback_requested" => "Balanced?" }),
      )

    expect(raw).to start_with("![My Image](#{main.short_url})")
    expect(raw).to include('<div class="npn-critique-guidance">')
    expect(raw).to include("<strong>Critique Style:</strong> Standard")
    expect(raw).to include("<strong>Feedback Focus:</strong> Artistic / Expressive")
    expect(raw).to include("### Feedback Requested\n\nBalanced?")
    expect(raw).not_to include("### About This Image")
    expect(raw).not_to include("### Technical Details")
  end

  it "uses title-cased critique style and feedback focus labels" do
    raw =
      described_class.build(
        submission(
          critique_style: "in_depth",
          feedback_focus: "technical",
          fields: {
            "creative_direction" => "Quiet mood.",
            "feedback_requested" => "Where to focus.",
            "technical_details" => "ISO 100, f/8, 1/60s.",
          },
        ),
      )

    expect(raw).to include("<strong>Critique Style:</strong> In-Depth")
    expect(raw).to include("<strong>Feedback Focus:</strong> Technical Help")
  end

  it "labels the combined feedback focus as Artistic + Technical" do
    raw =
      described_class.build(
        submission(
          critique_style: "standard",
          feedback_focus: "both",
          fields: {
            "feedback_requested" => "x",
          },
        ),
      )

    expect(raw).to include("<strong>Feedback Focus:</strong> Artistic + Technical")
  end

  it "orders the simplified in-depth flow: About → Why → Express → Where Feedback Helps" do
    raw =
      described_class.build(
        submission(
          critique_style: "in_depth",
          fields: {
            "about_this_image" => "Quiet coastal morning.",
            "creative_intent" => "Drawn to the contemplative light.",
            "creative_direction" => "Aiming for stillness and breath.",
            "feedback_requested" => "Does the stillness read?",
          },
        ),
      )

    expect(raw).to include("### About This Image\n\nQuiet coastal morning.")
    expect(raw).to include("### Why This Image?\n\nDrawn to the contemplative light.")
    expect(raw).to include(
      "### What I’m Trying to Express or Explore\n\nAiming for stillness and breath.",
    )
    expect(raw).to include("### Where Feedback Would Help Most\n\nDoes the stillness read?")
    expect(raw.index("### About This Image")).to be < raw.index("### Why This Image?")
    expect(raw.index("### Why This Image?")).to be <
      raw.index("### What I’m Trying to Express or Explore")
    expect(raw.index("### What I’m Trying to Express or Explore")).to be <
      raw.index("### Where Feedback Would Help Most")
  end

  it "omits optional in-depth sections when their fields are blank" do
    raw =
      described_class.build(
        submission(
          critique_style: "in_depth",
          fields: {
            "feedback_requested" => "Where to focus?",
            "about_this_image" => "  ",
            "creative_intent" => "",
            "creative_direction" => "   ",
          },
        ),
      )

    expect(raw).to include("### Where Feedback Would Help Most")
    expect(raw).not_to include("### About This Image")
    expect(raw).not_to include("### Why This Image?")
    expect(raw).not_to include("### What I’m Trying to Express or Explore")
  end

  it "drops legacy Self-Critique data silently from in-depth posts" do
    raw =
      described_class.build(
        submission(
          critique_style: "in_depth",
          fields: {
            "self_critique" => "Leaked beta worksheet content.",
            "feedback_requested" => "Where to focus.",
          },
        ),
      )

    expect(raw).to include("### Where Feedback Would Help Most")
    expect(raw).not_to include("Self-Critique")
    expect(raw).not_to include("Leaked beta worksheet content.")
  end

  it "keeps Standard's heading as 'Feedback Requested' (not the in-depth wording)" do
    raw =
      described_class.build(
        submission(
          critique_style: "standard",
          fields: {
            "about_this_image" => "Context.",
            "feedback_requested" => "Balanced?",
          },
        ),
      )

    expect(raw).to include("### Feedback Requested\n\nBalanced?")
    expect(raw).not_to include("Where Feedback Would Help Most")
  end

  it "never renders the new in-depth headings for standard or initial-reaction" do
    %w[standard reaction].each do |style|
      raw =
        described_class.build(
          submission(
            critique_style: style,
            fields: {
              "feedback_requested" => "FR",
              "questions_for_viewers" => "Q?",
              # If (somehow) present, only the in-depth flow surfaces them.
              "creative_intent" => "leaked-why",
              "creative_direction" => "leaked-express",
            },
          ),
        )

      expect(raw).not_to include("Why This Image?"), "style=#{style}"
      expect(raw).not_to include("What I’m Trying to Express or Explore"), "style=#{style}"
      expect(raw).not_to include("Where Feedback Would Help Most"), "style=#{style}"
      expect(raw).not_to include("leaked-why"), "style=#{style}"
      expect(raw).not_to include("leaked-express"), "style=#{style}"
    end
  end

  it "hides initial-reaction notes in a spoiler (never details)" do
    raw =
      described_class.build(
        submission(
          critique_style: "reaction",
          fields: {
            "questions_for_viewers" => "Q",
            "about_this_image" => "A",
            "feedback_after" => "F",
          },
        ),
      )

    expect(raw).to include("### Questions for Viewers")
    expect(raw).to include("[spoiler]")
    expect(raw).to include("[/spoiler]")
    expect(raw).not_to include("[details]")
    expect(raw.index("### Questions for Viewers")).to be < raw.index("[spoiler]")
    expect(raw.index("[spoiler]")).to be < raw.index("### About This Image")
  end

  it "omits the spoiler block when all hidden fields are blank" do
    raw =
      described_class.build(
        submission(critique_style: "reaction", fields: { "questions_for_viewers" => "Q" }),
      )

    expect(raw).not_to include("[spoiler]")
  end

  it "renders additional images after the main image, using the note as alt text and an italic caption" do
    raw =
      described_class.build(
        submission(
          critique_style: "standard",
          fields: {
            "feedback_requested" => "x",
          },
          additional: [{ "upload_id" => variation.id, "note" => "Tighter crop" }],
        ),
      )

    expect(raw).to start_with("![My Image](#{main.short_url})")
    expect(raw).to include("![Tighter crop](#{variation.short_url})")
    expect(raw).to include("*Tighter crop*")
    expect(raw.index(main.short_url)).to be < raw.index(variation.short_url)
  end

  it "falls back to a numbered alt text for additional images without a note" do
    raw =
      described_class.build(
        submission(
          critique_style: "standard",
          fields: {
            "feedback_requested" => "x",
          },
          additional: [{ "upload_id" => variation.id, "note" => "" }],
        ),
      )

    expect(raw).to include("![Additional image 1](#{variation.short_url})")
  end

  it "renders images from the unified images array in order" do
    sub =
      DiscourseNpnSubmissions::Submission.new(
        user_id: user.id,
        submission_type: "image",
        status: "draft",
        critique_style: "standard",
        title: "My Image",
        data: {
          "feedback_focus" => "artistic",
          "images" => [
            { "upload_id" => main.id, "note" => "" },
            { "upload_id" => variation.id, "note" => "Crop" },
          ],
          "fields" => {
            "feedback_requested" => "x",
          },
        },
      )
    raw = described_class.build(sub)

    expect(raw).to start_with("![My Image](#{main.short_url})")
    expect(raw).to include("![Crop](#{variation.short_url})")
    expect(raw.index(main.short_url)).to be < raw.index(variation.short_url)
  end

  describe "Technical Details section" do
    it "renders text only under the heading" do
      raw =
        described_class.build(
          submission(
            critique_style: "standard",
            fields: {
              "feedback_requested" => "x",
              "technical_details" => "f/8, 1/200s, ISO 100",
            },
          ),
        )

      expect(raw).to include("### Technical Details\n\nf/8, 1/200s, ISO 100")
      expect(raw).not_to include(meta.short_url)
    end

    it "preserves line breaks between multi-line technical metadata" do
      raw =
        described_class.build(
          submission(
            critique_style: "standard",
            fields: {
              "feedback_requested" => "x",
              "technical_details" => "Camera: Canon EOS R5\nLens: RF14-35mm F4\nISO: 100",
            },
          ),
        )

      # Each metadata line ends with a Markdown hard break (two trailing spaces)
      # so it renders on its own line; not collapsed into one paragraph.
      expect(raw).to include("Camera: Canon EOS R5  \nLens: RF14-35mm F4  \nISO: 100")
    end

    it "renders a metadata screenshot only under the heading" do
      raw =
        described_class.build(
          submission(
            critique_style: "standard",
            fields: {
              "feedback_requested" => "x",
            },
            metadata: meta,
          ),
        )

      expect(raw).to include("### Technical Details")
      expect(raw).to include("![Metadata screenshot](#{meta.short_url})")
      # Wrapped in the scoped class so plugin CSS can render it as secondary
      # supporting context, with blank lines so the image still cooks.
      expect(raw).to include("<div class=\"npn-metadata-screenshot\">\n\n![Metadata screenshot]")
      expect(raw).to include("</div>")
    end

    it "renders text first, then the screenshot, when both are present" do
      raw =
        described_class.build(
          submission(
            critique_style: "standard",
            fields: {
              "feedback_requested" => "x",
              "technical_details" => "f/8",
            },
            metadata: meta,
          ),
        )

      expect(raw.index("f/8")).to be < raw.index(meta.short_url)
    end

    it "omits the section when neither text nor screenshot is present" do
      raw =
        described_class.build(
          submission(critique_style: "standard", fields: { "feedback_requested" => "x" }),
        )

      expect(raw).not_to include("### Technical Details")
    end

    it "places the metadata screenshot inside the spoiler for initial reaction" do
      raw =
        described_class.build(
          submission(
            critique_style: "reaction",
            fields: {
              "questions_for_viewers" => "Q",
            },
            metadata: meta,
          ),
        )

      expect(raw).to include("[spoiler]")
      expect(raw.index("[spoiler]")).to be < raw.index(meta.short_url)
      expect(raw.index(meta.short_url)).to be < raw.index("[/spoiler]")
    end
  end

  describe "weekly challenge section" do
    def weekly_submission
      DiscourseNpnSubmissions::Submission.new(
        user_id: user.id,
        submission_type: "weekly_challenge",
        status: "draft",
        critique_style: "standard",
        title: "My Image",
        data: {
          "feedback_focus" => "artistic",
          "images" => [{ "upload_id" => main.id, "note" => "" }],
          "fields" => {
            "feedback_requested" => "Balanced?",
          },
        },
      )
    end

    it "renders the title and dates as a context callout after the image, before the guidance" do
      allow(DiscourseNpnSubmissions::WeeklyChallengeInfo).to receive(:current).and_return(
        {
          title: "Quiet Geometry",
          dates: "May 20–26, 2026",
          description: "ignored",
          url: "https://e/c",
        },
      )

      raw = described_class.build(weekly_submission)

      expect(raw).to include('<div class="npn-weekly-challenge-context">')
      expect(raw).to include("<h3>Weekly Challenge</h3>")
      expect(raw).to include('<div class="npn-weekly-challenge-title">Quiet Geometry</div>')
      expect(raw).to include('<div class="npn-weekly-challenge-dates">May 20–26, 2026</div>')
      expect(raw.index("![My Image]")).to be < raw.index("npn-weekly-challenge-context")
      expect(raw.index("npn-weekly-challenge-context")).to be < raw.index("npn-critique-guidance")
    end

    it "does not include the description in the post" do
      allow(DiscourseNpnSubmissions::WeeklyChallengeInfo).to receive(:current).and_return(
        { title: "Quiet Geometry", dates: nil, description: "The full prompt text.", url: nil },
      )

      raw = described_class.build(weekly_submission)
      expect(raw).to include('<div class="npn-weekly-challenge-title">Quiet Geometry</div>')
      expect(raw).not_to include("The full prompt text.")
    end

    it "omits the dates div when dates are absent" do
      allow(DiscourseNpnSubmissions::WeeklyChallengeInfo).to receive(:current).and_return(
        { title: "Quiet Geometry", dates: nil, description: nil, url: nil },
      )

      raw = described_class.build(weekly_submission)
      expect(raw).to include('<div class="npn-weekly-challenge-title">Quiet Geometry</div>')
      expect(raw).not_to include("npn-weekly-challenge-dates")
    end

    it "escapes HTML in the synced values" do
      allow(DiscourseNpnSubmissions::WeeklyChallengeInfo).to receive(:current).and_return(
        { title: "Shapes & <Light>", dates: nil, description: nil, url: nil },
      )

      raw = described_class.build(weekly_submission)
      expect(raw).to include(
        '<div class="npn-weekly-challenge-title">Shapes &amp; &lt;Light&gt;</div>',
      )
    end

    it "omits the section entirely when sync is unavailable" do
      allow(DiscourseNpnSubmissions::WeeklyChallengeInfo).to receive(:current).and_return(nil)

      raw = described_class.build(weekly_submission)
      expect(raw).not_to include("npn-weekly-challenge-context")
    end

    it "never adds the section to a non-weekly submission" do
      allow(DiscourseNpnSubmissions::WeeklyChallengeInfo).to receive(:current).and_return(
        { title: "Quiet Geometry", dates: nil, description: nil, url: nil },
      )

      raw =
        described_class.build(
          submission(critique_style: "standard", fields: { "feedback_requested" => "x" }),
        )
      expect(raw).not_to include("npn-weekly-challenge-context")
    end

    it "does not invoke the WordPress sync at all for a non-weekly submission" do
      # weekly_challenge_section must bail before touching WeeklyChallengeInfo, so
      # a standard Image Critique can never crash on weekly-challenge code.
      allow(DiscourseNpnSubmissions::WeeklyChallengeInfo).to receive(:current)

      described_class.build(
        submission(critique_style: "standard", fields: { "feedback_requested" => "x" }),
      )

      expect(DiscourseNpnSubmissions::WeeklyChallengeInfo).not_to have_received(:current)
    end
  end
end
