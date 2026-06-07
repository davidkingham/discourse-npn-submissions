# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnSubmissions::IntroductionPostBuilder do
  fab!(:user)
  fab!(:upload) { Fabricate(:upload, user: user) }

  def submission(fields:, images: [], title: "Hello from Colorado")
    DiscourseNpnSubmissions::Submission.new(
      user_id: user.id,
      submission_type: "introduction",
      status: "draft",
      critique_style: nil,
      title: title,
      data: {
        "images" => images,
        "fields" => fields,
      },
    )
  end

  it "renders About Me and the optional learning section when both are provided" do
    md =
      described_class.build(
        submission(
          fields: {
            "about" => "I make quiet landscape work from Colorado.",
            "learning" => "Hoping to improve my sequencing and find a critique community.",
          },
        ),
      )

    expect(md).to include("### About Me\n\nI make quiet landscape work from Colorado.")
    expect(md).to include(
      "### What I’m Hoping to Learn or Explore\n\nHoping to improve my sequencing and find a critique community.",
    )
    expect(md.index("### About Me")).to be < md.index("### What I’m Hoping to Learn or Explore")
  end

  it "omits the learning section when it is blank" do
    md =
      described_class.build(
        submission(fields: { "about" => "Just here to say hi.", "learning" => "" }),
      )
    expect(md).to include("### About Me")
    expect(md).not_to include("What I’m Hoping to Learn or Explore")
  end

  it "omits the learning section when it is whitespace-only" do
    md = described_class.build(submission(fields: { "about" => "Hi.", "learning" => "   " }))
    expect(md).not_to include("What I’m Hoping to Learn or Explore")
  end

  it "renders the optional image as a Markdown image at the top of the post" do
    md =
      described_class.build(
        submission(
          fields: {
            "about" => "Hi all.",
          },
          images: [{ "upload_id" => upload.id }],
          title: "Hello from the Sierras",
        ),
      )

    expect(md).to start_with("![Hello from the Sierras](#{upload.short_url})")
    expect(md.index("![Hello from the Sierras](")).to be < md.index("### About Me")
  end

  it "uses a fallback alt text when the title is blank" do
    md =
      described_class.build(
        submission(
          fields: {
            "about" => "Hi.",
          },
          images: [{ "upload_id" => upload.id }],
          title: "   ",
        ),
      )

    expect(md).to include("![Introduction image](#{upload.short_url})")
  end

  it "renders cleanly with just About Me when there's no image or learning text" do
    md = described_class.build(submission(fields: { "about" => "Solo intro." }))

    expect(md).to eq("### About Me\n\nSolo intro.")
    expect(md).not_to include("Image")
    expect(md).not_to include("Learning")
  end

  it "never emits critique/project/weekly markup" do
    md =
      described_class.build(
        submission(
          fields: {
            "about" => "A.",
            "learning" => "B.",
          },
          images: [{ "upload_id" => upload.id }],
        ),
      )

    expect(md).not_to include("npn-critique-guidance")
    expect(md).not_to include("npn-weekly-challenge-context")
    expect(md).not_to include("npn-project-overview-grid")
    expect(md).not_to include("npn-project-submission:begin")
    expect(md).not_to include("Technical Details")
    expect(md).not_to include("Feedback Requested")
    expect(md).not_to include("Critique Style")
  end
end
