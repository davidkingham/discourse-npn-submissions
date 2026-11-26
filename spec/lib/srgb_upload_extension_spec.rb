# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnSubmissions::SrgbUploadExtension do
  fab!(:user)

  let(:fixtures) { File.expand_path("../fixtures/images", __dir__) }

  before do
    SiteSetting.npn_submissions_enabled = true
    SiteSetting.npn_submissions_convert_uploads_to_srgb = true
  end

  def upload_fixture(name)
    # UploadCreator rewrites the file in place, so work on a copy.
    tmp = Tempfile.new(["npn-srgb", File.extname(name)])
    tmp.binmode
    tmp.write(File.binread(File.join(fixtures, name)))
    tmp.rewind
    # Image processing (including the orientation step this hooks into) is
    # skipped in the test env unless forced.
    UploadCreator.new(tmp, name, force_optimize: true).create_for(user.id)
  end

  def icc_description(upload)
    path = Discourse.store.path_for(upload)
    Discourse::Utils.execute_command(
      "magick",
      "identify",
      "-ping",
      "-format",
      "%[profile:icc]",
      "#{path}[0]",
    ).strip
  end

  def mean_rgb(path)
    Discourse::Utils
      .execute_command(
        "magick",
        path,
        "-profile",
        Rails.root.join("vendor/data/RT_sRGB.icm").to_s,
        "-format",
        "%[fx:mean.r] %[fx:mean.g] %[fx:mean.b]",
        "info:",
      )
      .split
      .map(&:to_f)
  end

  it "converts a ProPhoto JPEG to sRGB" do
    upload = upload_fixture("prophoto.jpg")

    expect(upload).to be_persisted
    expect(icc_description(upload)).to match(/srgb/i)
    expect(upload.width).to eq(64)
    expect(upload.height).to eq(48)
    expect(upload.sha1).to eq(Upload.generate_digest(Discourse.store.path_for(upload)))
    expect(upload.filesize).to eq(File.size(Discourse.store.path_for(upload)))
  end

  it "keeps the colours the same when converting" do
    upload = upload_fixture("prophoto.jpg")
    before = mean_rgb(File.join(fixtures, "prophoto.jpg"))
    after = mean_rgb(Discourse.store.path_for(upload))

    before.zip(after).each { |b, a| expect(a).to be_within(0.02).of(b) }
  end

  it "converts a ProPhoto PNG to sRGB" do
    upload = upload_fixture("prophoto.png")

    expect(upload).to be_persisted
    expect(icc_description(upload)).to match(/srgb/i)
  end

  it "leaves an sRGB image byte-for-byte untouched by the conversion" do
    UploadCreator.any_instance.expects(:npn_convert_to_srgb!).never
    upload = upload_fixture("srgb.jpg")

    expect(upload).to be_persisted
    expect(icc_description(upload)).to eq("sRGB IEC61966-2.1")
  end

  it "leaves images with no profile alone" do
    UploadCreator.any_instance.expects(:npn_convert_to_srgb!).never
    expect(upload_fixture("no_profile.jpg")).to be_persisted
  end

  it "leaves grayscale images alone" do
    UploadCreator.any_instance.expects(:npn_convert_to_srgb!).never
    expect(upload_fixture("gray.jpg")).to be_persisted
  end

  it "does nothing when the setting is off" do
    SiteSetting.npn_submissions_convert_uploads_to_srgb = false
    upload = upload_fixture("prophoto.jpg")

    expect(icc_description(upload)).to eq("ProPhoto RGB")
  end

  it "stores the original unconverted if the conversion fails" do
    UploadCreator.any_instance.stubs(:npn_srgb_profile_path).returns("/nonexistent/sRGB.icm")
    upload = upload_fixture("prophoto.jpg")

    expect(upload).to be_persisted
    expect(icc_description(upload)).to eq("ProPhoto RGB")
  end
end
