# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnSubmissions::IccProfile do
  let(:fixtures) { File.expand_path("../fixtures/images", __dir__) }

  def read(name)
    described_class.read(File.join(fixtures, name))
  end

  it "reads the profile name and colour space from JPEG and PNG files" do
    expect(read("prophoto.jpg")).to eq(name: "ProPhoto RGB", space: "RGB")
    expect(read("prophoto.png")).to eq(name: "ProPhoto RGB", space: "RGB")
    expect(read("adobergb.jpg")).to eq(name: "Adobe RGB (1998)", space: "RGB")
    expect(read("p3.jpg")).to eq(name: "Display P3", space: "RGB")
    expect(read("srgb.jpg")).to eq(name: "sRGB IEC61966-2.1", space: "RGB")
    expect(read("unrecognised.jpg")).to eq(name: "Generic RGB Profile", space: "RGB")
  end

  it "reads the sRGB profile core converts to" do
    profile = described_class.parse(File.binread(Rails.root.join("vendor/data/RT_sRGB.icm")))

    expect(profile[:name]).to match(/srgb/i)
  end

  it "returns nil for files with no readable profile" do
    truncated = Tempfile.new(%w[npn-icc .jpg])
    truncated.binmode
    truncated.write(File.binread(File.join(fixtures, "prophoto.jpg"), 60))
    truncated.flush

    expect(read("no_profile.jpg")).to be_nil
    expect(read("gray.jpg")).to be_nil
    expect(described_class.read(truncated.path)).to be_nil
    expect(described_class.read(__FILE__)).to be_nil
    expect(described_class.read("/nonexistent/photo.jpg")).to be_nil
  end
end
