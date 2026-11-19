# frozen_string_literal: true

require "rails_helper"

# Fallback project images read from the first post of a project topic that has
# no submission row. Fixtures mirror the formats found on the live forum.
describe DiscourseNpnSubmissions::ProjectPostImages do
  fab!(:user) { Fabricate(:user, trust_level: TrustLevel[2]) }
  fab!(:uploads) { Array.new(6) { Fabricate(:upload, user: user) } }

  def topic_with(raw)
    topic = Fabricate(:topic, user: user)
    Fabricate(:post, topic: topic, user: user, raw: raw)
    topic.reload
  end

  def numbers(result)
    result[:originals].map { |i| i[:number] }
  end

  def ids(list)
    list.map { |i| i[:upload_id] }
  end

  def full_url(upload)
    "https://images.example.com/original/3X/a/b/#{upload.sha1}.jpeg"
  end

  it "reads the current form's Image Sequence and Alternate Images" do
    a, b, c, alt = uploads
    raw = <<~MD
      <!-- npn-project-submission:begin -->

      ### Project Overview

      <div class="npn-project-overview-grid">
      <img class="npn-project-overview-image" src="/x.jpg" alt="Image 1">
      </div>

      ### Image Sequence

      **Image 1**

      ![Image 1](#{a.short_url})

      *A caption*

      **Image 2**

      ![Image 2](#{b.short_url})

      **Image 3**

      ![Image 3](#{c.short_url})

      <!-- npn-project-submission:end -->

      ### Brief Project Description

      Words.

      ### Alternate Images

      ![Alternate 1](#{alt.short_url})
    MD

    result = described_class.build(topic_with(raw))
    expect(numbers(result)).to eq(%w[1 2 3])
    expect(ids(result[:originals])).to eq([a.id, b.id, c.id])
    expect(ids(result[:alternates])).to eq([alt.id])
    expect(result[:alternates].first[:number]).to eq("A1")
    expect(result[:source]).to eq("post")
  end

  it "uses the revised sequence and ignores the Original Submission copy" do
    a, b, c, d = uploads
    raw = <<~MD
      <!-- npn-project-submission:begin -->

      ### Image Sequence

      **Image 1**

      ![Image 1](#{a.short_url})

      **Image 2**

      ![Image 2](#{b.short_url})

      [details="Original Submission"]

      ### Image Sequence

      ![Image 1](#{c.short_url})

      ![Image 2](#{d.short_url})

      [/details]

      <!-- npn-project-submission:end -->
    MD

    result = described_class.build(topic_with(raw))
    expect(ids(result[:originals])).to eq([a.id, b.id])
  end

  it "skips revision blocks before the original sequence" do
    a, b, c, revised = uploads
    raw = <<~MD
      <!-- revised-critique-image:begin -->
      ## Revised Version

      ### Revision 1

      ![Revised version|1440x1800](#{revised.short_url})
      <!-- revised-critique-image:end -->

      ## Original Version

      ### Image Sequence

      ![Image 1](#{a.short_url})

      ![Image 2](#{b.short_url})

      ![Image 3](#{c.short_url})
    MD

    result = described_class.build(topic_with(raw))
    expect(ids(result[:originals])).to eq([a.id, b.id, c.id])
  end

  it "reads the older masonry form once (Individual Images), by full URL, with alternates" do
    a, b, c, alt = uploads
    raw = <<~MD
      ## Project Images

      **Gallery Overview**

      <div data-masonry-gallery>
      ![Image 1](#{full_url(a)})
      ![Image 2](#{full_url(b)})
      ![Image 3](#{full_url(c)})
      </div>

      **Individual Images**

      ![Image 1](#{full_url(a)})
      **Image 1**

      ![Image 2](#{full_url(b)})
      **Image 2**

      ![Image 3](#{full_url(c)})
      **Image 3**
      "Third one"

      ## Project Description

      Words.

      ## Alternate Images

      ![Alternate 1](#{full_url(alt)})
      **Alternate Image 1**
    MD

    result = described_class.build(topic_with(raw))
    expect(ids(result[:originals])).to eq([a.id, b.id, c.id])
    expect(ids(result[:alternates])).to eq([alt.id])
  end

  it "skips a cover image placed before the first heading" do
    cover, a, b, c = uploads
    raw = <<~MD
      ![Cloud Illusions Image|453x500](#{cover.short_url})
      ### Brief Project Description

      Words.

      ### Presentation Goal

      Other

      **Additional Details:** more words.
      ![Cloud Illusions|690x460](#{a.short_url})
      ![Cloud Illusions-2|530x500](#{b.short_url})
      ![Cloud Illusions-3|690x430](#{c.short_url})
    MD

    result = described_class.build(topic_with(raw))
    expect(ids(result[:originals])).to eq([a.id, b.id, c.id])
  end

  it "reads the presentation goal from the post" do
    a, b = uploads
    raw = <<~MD
      ### Image Sequence

      ![Image 1](#{a.short_url})

      ![Image 2](#{b.short_url})

      ### Presentation Goal

      Gallery Exhibition
    MD
    expect(described_class.build(topic_with(raw))[:intent]).to eq("gallery")

    other = raw.sub("Gallery Exhibition", "Other\n\n**Additional Details:** a zine")
    expect(described_class.build(topic_with(other))[:intent]).to eq("other")

    none = raw.sub(/### Presentation Goal.*/m, "")
    expect(described_class.build(topic_with(none))[:intent]).to be_nil
  end

  it "returns nil when there are fewer than two project images" do
    raw = <<~MD
      ## Project Images

      [My eBook](https://example.com/ebook)

      <div data-masonry-gallery></div>
    MD
    expect(described_class.build(topic_with(raw))).to be_nil

    one = topic_with("### Image Sequence\n\n![Image 1](#{uploads.first.short_url})\n")
    expect(described_class.build(one)).to be_nil
  end

  it "ignores images it can't match to an upload" do
    a, b = uploads
    raw = <<~MD
      ### Image Sequence

      ![Image 1](#{a.short_url})

      ![Elsewhere](https://example.com/not-an-upload.jpg)

      ![Image 2](#{b.short_url})
    MD

    result = described_class.build(topic_with(raw))
    expect(ids(result[:originals])).to eq([a.id, b.id])
  end
end
