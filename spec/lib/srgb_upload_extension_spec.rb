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

  def profile_of(path)
    Discourse::Utils.execute_command(
      "magick",
      "identify",
      "-ping",
      "-format",
      "%[profile:icc]",
      "#{path}[0]",
    ).strip
  end

  def stored_profile(upload)
    profile_of(Discourse.store.path_for(upload))
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

  it "converts a ProPhoto JPEG to sRGB and records the converted file" do
    upload = upload_fixture("prophoto.jpg")
    stored_path = Discourse.store.path_for(upload)

    expect(upload).to be_persisted
    expect(stored_profile(upload)).to match(/srgb/i)
    expect([upload.width, upload.height]).to eq([64, 48])
    expect(upload.sha1).to eq(Upload.generate_digest(stored_path))
    expect(upload.filesize).to eq(File.size(stored_path))
  end

  it "keeps the colours the same when converting" do
    upload = upload_fixture("prophoto.jpg")
    original = mean_rgb(File.join(fixtures, "prophoto.jpg"))
    converted = mean_rgb(Discourse.store.path_for(upload))

    original
      .zip(converted)
      .each do |original_channel, converted_channel|
        expect(converted_channel).to be_within(0.02).of(original_channel)
      end
  end

  it "converts a ProPhoto PNG to sRGB" do
    upload = upload_fixture("prophoto.png")

    expect(upload).to be_persisted
    expect(stored_profile(upload)).to match(/srgb/i)
  end

  it "converts a profile it does not recognise to sRGB" do
    upload = upload_fixture("unrecognised.jpg")

    expect(upload).to be_persisted
    expect(stored_profile(upload)).to match(/srgb/i)
  end

  %w[srgb.jpg adobergb.jpg p3.jpg].each do |name|
    it "keeps the profile of #{name}" do
      upload = upload_fixture(name)

      expect(upload).to be_persisted
      expect(stored_profile(upload)).to eq(profile_of(File.join(fixtures, name)))
    end
  end

  it "stores images with no profile and grayscale images without adding one" do
    no_profile = upload_fixture("no_profile.jpg")
    gray = upload_fixture("gray.jpg")

    expect(no_profile).to be_persisted
    expect(gray).to be_persisted
    expect(stored_profile(no_profile)).to eq("")
    expect(stored_profile(gray)).to eq("")
  end

  it "keeps a ProPhoto profile when the setting is off" do
    SiteSetting.npn_submissions_convert_uploads_to_srgb = false
    upload = upload_fixture("prophoto.jpg")

    expect(stored_profile(upload)).to eq("ProPhoto RGB")
  end

  it "stores the original unconverted when the conversion fails" do
    UploadCreator.any_instance.stubs(:npn_srgb_profile_path).returns("/nonexistent/sRGB.icm")
    upload = upload_fixture("prophoto.jpg")

    expect(upload).to be_persisted
    expect(stored_profile(upload)).to eq("ProPhoto RGB")
  end
end
