# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnSubmissions::ProjectPostBuilder do
  fab!(:user)
  fab!(:upload1) { Fabricate(:upload, user: user) }
  fab!(:upload2) { Fabricate(:upload, user: user) }
  fab!(:alt1) { Fabricate(:upload, user: user) }

  def fields(extra = {})
    {
      "project_description" => "A cohesive body of work.",
      "self_critique" => "Working: mood. Improve: sequencing.",
      "creative_direction" => "Quiet and contemplative.",
      "feedback_requested" => "Does the sequence cohere?",
      "project_intent" => "gallery",
    }.merge(extra)
  end

  def submission(data)
    DiscourseNpnSubmissions::Submission.new(
      submission_type: "project",
      title: "My Project",
      data: data,
      user: user,
    )
  end

  it "builds an images project with normal images and h3 sections" do
    md =
      described_class.build(
        submission(
          "method" => "images",
          "feedback_focus" => "artistic",
          "images" => [{ "upload_id" => upload1.id }, { "upload_id" => upload2.id }],
          "fields" => fields,
        ),
      )

    # Contact-sheet overview grid, then the full images in sequence.
    expect(md).to include("### Project Overview")
    expect(md).to include("### Image Sequence")
    expect(md.index("### Project Overview")).to be < md.index("### Image Sequence")
    expect(md).not_to include("data-masonry-gallery")

    # Overview: raw-HTML grid referencing real upload URLs, with the number in a
    # label row ABOVE the image (in a fixed frame) — never overlaid on the photo.
    expect(md).to include('<div class="npn-project-overview-grid">')
    expect(md).to include('<div class="npn-project-overview-frame">')
    expect(md).to include('class="npn-project-overview-image"')
    expect(md).to include('<div class="npn-project-overview-label">Image 1</div>')
    expect(md).to include('<div class="npn-project-overview-label">Image 2</div>')
    expect(md).not_to include("npn-project-overview-number")
    # Label comes before its image within the cell.
    expect(md.index('npn-project-overview-label">Image 1')).to be < md.index(upload1.url)
    expect(md).to include(upload1.url)
    expect(md).to include(upload2.url)

    # Sequence: a bold "Image N" label before each full Markdown image.
    expect(md).to include("**Image 1**")
    expect(md).to include("**Image 2**")
    expect(md).to include("![Image 1](#{upload1.short_url})")
    expect(md).to include("![Image 2](#{upload2.short_url})")
    expect(md.index("**Image 1**")).to be < md.index("![Image 1](#{upload1.short_url})")

    expect(md).to include("### Brief Project Description")
    expect(md).to include("### Self-Critique")
    expect(md).to include("### Creative Direction")
    expect(md).to include("### Feedback Requested")
    expect(md).to include("### Presentation Goal")
    expect(md).to include("Gallery Exhibition")

    # Narrative order: description → creative direction → self-critique →
    # feedback requested → presentation goal.
    expect(md.index("### Brief Project Description")).to be < md.index("### Creative Direction")
    expect(md.index("### Creative Direction")).to be < md.index("### Self-Critique")
    expect(md.index("### Self-Critique")).to be < md.index("### Feedback Requested")
    expect(md.index("### Feedback Requested")).to be < md.index("### Presentation Goal")
  end

  it "renders Additional Details under Presentation Goal as a bold sub-line" do
    md =
      described_class.build(
        submission(
          "method" => "images",
          "feedback_focus" => "artistic",
          "images" => [{ "upload_id" => upload1.id }],
          "fields" => fields("project_intent_details" => "Targeting Issue 42."),
        ),
      )

    expect(md).to include("### Presentation Goal")
    expect(md).to include("**Additional Details:** Targeting Issue 42.")
    # The label is part of the Presentation Goal section, after the goal value.
    expect(md.index("### Presentation Goal")).to be < md.index("**Additional Details:**")
  end

  it "omits Additional Details when no details are provided" do
    md =
      described_class.build(
        submission(
          "method" => "images",
          "feedback_focus" => "artistic",
          "images" => [{ "upload_id" => upload1.id }],
          "fields" => fields,
        ),
      )

    expect(md).to include("### Presentation Goal")
    expect(md).not_to include("Additional Details")
  end

  it "numbers the overview left-to-right in submission order" do
    md =
      described_class.build(
        submission(
          "method" => "images",
          "feedback_focus" => "artistic",
          "images" => [{ "upload_id" => upload1.id }, { "upload_id" => upload2.id }],
          "fields" => fields,
        ),
      )

    expect(md.index(upload1.url)).to be < md.index(upload2.url)
    expect(md.index('npn-project-overview-label">Image 1')).to be <
      md.index('npn-project-overview-label">Image 2')
  end

  it "shows an image note below its full image in the sequence when present" do
    md =
      described_class.build(
        submission(
          "method" => "images",
          "feedback_focus" => "artistic",
          "images" => [{ "upload_id" => upload1.id, "note" => "Opening frame" }],
          "fields" => fields,
        ),
      )

    expect(md).to include("*Opening frame*")
    expect(md.index("![Image 1](#{upload1.short_url})")).to be < md.index("*Opening frame*")
  end

  it "preserves main image order" do
    md =
      described_class.build(
        submission(
          "method" => "images",
          "feedback_focus" => "both",
          "images" => [{ "upload_id" => upload2.id }, { "upload_id" => upload1.id }],
          "fields" => fields,
        ),
      )
    expect(md.index(upload2.short_url)).to be < md.index(upload1.short_url)
  end

  it "includes an alternates gallery when alternates are present" do
    md =
      described_class.build(
        submission(
          "method" => "images",
          "feedback_focus" => "artistic",
          "images" => [{ "upload_id" => upload1.id }],
          "alternates" => [{ "upload_id" => alt1.id }],
          "fields" => fields,
        ),
      )
    expect(md).to include("### Alternate Images")
    expect(md).to include(alt1.short_url)
  end

  it "renders a PDF project as an access card with the representative image as a thumbnail" do
    pdf = Fabricate(:upload, user: user)
    rep = Fabricate(:upload, user: user)
    md =
      described_class.build(
        submission(
          "method" => "pdf",
          "feedback_focus" => "technical",
          "pdf_upload_id" => pdf.id,
          "representative_image_upload_id" => rep.id,
          "fields" => fields,
        ),
      )
    expect(md).to include('<div class="npn-project-access-card">')
    expect(md).to include("Project PDF")
    expect(md).to include(pdf.original_filename)
    expect(md).to include("Open PDF →")
    expect(md).to include(%(href="#{pdf.url}"))
    expect(md).to include(%(<img src="#{rep.url}"))
    # the card is the hero, not a standalone full image
    expect(md).not_to include("### Project File")
    expect(md).not_to include("![Representative image]")
    # card comes before the reflective sections
    expect(md.index("npn-project-access-card")).to be < md.index("### Brief Project Description")
  end

  it "renders a URL project as an access card with title, description and CTA" do
    rep = Fabricate(:upload, user: user)
    md =
      described_class.build(
        submission(
          "method" => "url",
          "feedback_focus" => "both",
          "link_url" => "https://example.com/project",
          "link_description" => "An external gallery.",
          "representative_image_upload_id" => rep.id,
          "fields" => fields,
        ),
      )
    expect(md).to include('<div class="npn-project-access-card">')
    expect(md).to include("Project Link")
    # the destination domain, not a repeat of the (topic) title
    expect(md).to include("example.com")
    expect(md).not_to include(%(<a href="https://example.com/project">My Project</a>))
    expect(md).to include("An external gallery.")
    expect(md).to include("View Project →")
    expect(md).to include(%(<img src="#{rep.url}"))
    expect(md).not_to include("### Project Link")
    expect(md.index("npn-project-access-card")).to be < md.index("### Brief Project Description")
  end

  it "appends additional intent details" do
    md =
      described_class.build(
        submission(
          "method" => "url",
          "feedback_focus" => "both",
          "link_url" => "https://example.com",
          "fields" => fields("project_intent" => "other", "project_intent_details" => "A zine."),
        ),
      )
    expect(md).to include("Other")
    expect(md).to include("**Additional Details:** A zine.")
  end

  describe "project-submission markers" do
    it "wraps the images-method generated block in begin/end markers" do
      md =
        described_class.build(
          submission(
            "method" => "images",
            "feedback_focus" => "artistic",
            "images" => [{ "upload_id" => upload1.id }, { "upload_id" => upload2.id }],
            "fields" => fields,
          ),
        )

      expect(md).to include("<!-- npn-project-submission:begin -->")
      expect(md).to include("<!-- npn-project-submission:end -->")
      # Markers bracket both the overview grid and the image sequence...
      expect(md.index("<!-- npn-project-submission:begin -->")).to be <
        md.index("### Project Overview")
      expect(md.index("### Image Sequence")).to be <
        md.index("<!-- npn-project-submission:end -->")
      # ...and the user-authored sections (Description, Creative Direction,
      # etc.) sit outside the marker block.
      expect(md.index("<!-- npn-project-submission:end -->")).to be <
        md.index("### Brief Project Description")
    end

    it "does not wrap PDF projects (no generated image grid)" do
      # Plain Fabricated upload — submission references it by id, the
      # actual extension doesn't matter for this test, and the test env
      # restricts non-image extensions.
      pdf_upload = Fabricate(:upload, user: user)
      thumb = Fabricate(:upload, user: user)
      md =
        described_class.build(
          submission(
            "method" => "pdf",
            "feedback_focus" => "both",
            "pdf_upload_id" => pdf_upload.id,
            "representative_image_upload_id" => thumb.id,
            "fields" => fields,
          ),
        )

      expect(md).not_to include("npn-project-submission")
    end

    it "does not wrap URL projects (no generated image grid)" do
      thumb = Fabricate(:upload, user: user)
      md =
        described_class.build(
          submission(
            "method" => "url",
            "feedback_focus" => "both",
            "link_url" => "https://example.com",
            "representative_image_upload_id" => thumb.id,
            "fields" => fields,
          ),
        )

      expect(md).not_to include("npn-project-submission")
    end
  end
end
