# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnSubmissions::NewMemberImagePostBuilder do
  fab!(:user)
  fab!(:upload) { Fabricate(:upload, user: user) }

  def submission(fields:, images: [{ "upload_id" => nil }], title: "Quiet coastal morning")
    images = [{ "upload_id" => upload.id }] if images == [{ "upload_id" => nil }]
    DiscourseNpnSubmissions::Submission.new(
      user_id: user.id,
      submission_type: "new_member_image",
      status: "draft",
      critique_style: nil,
      title: title,
      data: {
        "images" => images,
        "fields" => fields,
      },
    )
  end

  it "renders the image at the top, followed by About This Image and Feedback Welcome when both are provided" do
    md =
      described_class.build(
        submission(
          fields: {
            "about_this_image" => "Taken at first light from the bluffs.",
            "feedback" => "Curious what you notice first.",
          },
        ),
      )

    expect(md).to start_with("![Quiet coastal morning](#{upload.short_url})")
    expect(md).to include("### About This Image\n\nTaken at first light from the bluffs.")
    expect(md).to include("### Feedback Welcome\n\nCurious what you notice first.")
    expect(md.index("![Quiet coastal morning](")).to be < md.index("### About This Image")
    expect(md.index("### About This Image")).to be < md.index("### Feedback Welcome")
  end

  it "omits About This Image when blank" do
    md =
      described_class.build(
        submission(
          fields: { "about_this_image" => "   ", "feedback" => "Open to anything." },
        ),
      )
    expect(md).to include("### Feedback Welcome")
    expect(md).not_to include("About This Image")
  end

  it "omits Feedback Welcome when blank" do
    md =
      described_class.build(
        submission(fields: { "about_this_image" => "Brief context.", "feedback" => "" }),
      )
    expect(md).to include("### About This Image")
    expect(md).not_to include("Feedback Welcome")
  end

  it "renders just the image when no optional text is provided" do
    md = described_class.build(submission(fields: {}))
    expect(md).to eq("![Quiet coastal morning](#{upload.short_url})")
  end

  it "uses a fallback alt text when the title is blank" do
    md = described_class.build(submission(fields: {}, title: " "))
    expect(md).to include("![Image](#{upload.short_url})")
  end

  it "never emits critique/project/weekly/introduction markup" do
    md =
      described_class.build(
        submission(
          fields: { "about_this_image" => "X", "feedback" => "Y" },
        ),
      )

    expect(md).not_to include("npn-critique-guidance")
    expect(md).not_to include("npn-weekly-challenge-context")
    expect(md).not_to include("npn-project-overview-grid")
    expect(md).not_to include("npn-project-submission:begin")
    expect(md).not_to include("Technical Details")
    expect(md).not_to include("Feedback Requested")
    expect(md).not_to include("Critique Style")
    expect(md).not_to include("About Me")
    expect(md).not_to include("Hoping to Learn")
  end
end
