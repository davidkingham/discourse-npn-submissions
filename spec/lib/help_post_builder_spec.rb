# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnSubmissions::HelpPostBuilder do
  fab!(:user)
  fab!(:shot1) { Fabricate(:upload, user: user) }
  fab!(:shot2) { Fabricate(:upload, user: user) }

  def submission(fields: {}, images: [], title: "Can't upload my image")
    DiscourseNpnSubmissions::Submission.new(
      user_id: user.id,
      submission_type: "help",
      status: "draft",
      critique_style: nil,
      title: title,
      data: {
        "images" => images,
        "fields" => fields,
      },
    )
  end

  it "renders the description under '### What's happening'" do
    md =
      described_class.build(
        submission(fields: { "description" => "Upload spinner runs forever then 500s." }),
      )
    expect(md).to include("### What's happening\n\nUpload spinner runs forever then 500s.")
  end

  it "renders attached screenshots under '### Screenshots' with optional captions" do
    md =
      described_class.build(
        submission(
          fields: {
            "description" => "See attached.",
          },
          images: [
            { "upload_id" => shot1.id, "note" => "Before clicking Save" },
            { "upload_id" => shot2.id, "note" => "" },
          ],
        ),
      )

    expect(md).to include("### Screenshots")
    expect(md).to include("![Screenshot 1](#{shot1.short_url})")
    expect(md).to include("*Before clicking Save*")
    expect(md).to include("![Screenshot 2](#{shot2.short_url})")
    # First screenshot's caption goes between its image and the next image.
    expect(md.index("![Screenshot 1](")).to be < md.index("*Before clicking Save*")
    expect(md.index("*Before clicking Save*")).to be < md.index("![Screenshot 2](")
  end

  it "omits the Screenshots section entirely when no screenshots are attached" do
    md = described_class.build(submission(fields: { "description" => "Just text." }))
    expect(md).not_to include("Screenshots")
  end

  it "wraps the diagnostic info in a [details] block when provided" do
    diag = <<~MD.strip
      - **Browser:** Chrome 125
      - **OS:** macOS 14
      - **Device:** Desktop (1920×1080)
      - **Came from:** https://example.test/t/x/12345
    MD
    md =
      described_class.build(
        submission(fields: { "description" => "Stuck.", "diagnostic_info" => diag }),
      )

    expect(md).to include("[details=\"Diagnostic info\"]")
    expect(md).to include("- **Browser:** Chrome 125")
    expect(md).to include("[/details]")
    # Diagnostic block goes after the description.
    expect(md.index("### What's happening")).to be < md.index("[details=")
  end

  it "omits the diagnostic block when the field is empty (user opted out)" do
    md =
      described_class.build(
        submission(fields: { "description" => "No diag here.", "diagnostic_info" => "" }),
      )
    expect(md).not_to include("[details=")
    expect(md).not_to include("Diagnostic info")
  end

  it "omits the diagnostic block when the field is whitespace-only" do
    md =
      described_class.build(
        submission(fields: { "description" => "x", "diagnostic_info" => "   \n   " }),
      )
    expect(md).not_to include("Diagnostic info")
  end

  it "never emits critique/project/weekly/intro/new-member-image markup" do
    md =
      described_class.build(
        submission(
          fields: {
            "description" => "issue",
            "diagnostic_info" => "- **Browser:** X",
          },
          images: [{ "upload_id" => shot1.id }],
        ),
      )

    expect(md).not_to include("npn-critique-guidance")
    expect(md).not_to include("npn-weekly-challenge-context")
    expect(md).not_to include("npn-project-overview-grid")
    expect(md).not_to include("npn-project-submission:begin")
    expect(md).not_to include("Technical Details")
    expect(md).not_to include("Feedback Requested")
    expect(md).not_to include("About Me")
    expect(md).not_to include("Feedback Welcome")
  end
end
