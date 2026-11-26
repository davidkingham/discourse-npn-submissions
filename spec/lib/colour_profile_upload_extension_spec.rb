# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnSubmissions::ColourProfileUploadExtension do
  fab!(:user)
  fab!(:admin)

  let(:fixtures) { File.expand_path("../fixtures/images", __dir__) }

  before do
    SiteSetting.npn_submissions_enabled = true
    SiteSetting.npn_submissions_block_unsupported_colour_profiles = true
  end

  def upload_fixture(name, opts = {}, uploader: user)
    # UploadCreator may rewrite the file in place, so work on a copy.
    tmp = Tempfile.new(["npn-profile", File.extname(name)])
    tmp.binmode
    tmp.write(File.binread(File.join(fixtures, name)))
    tmp.rewind
    UploadCreator.new(tmp, name, opts).create_for(uploader.id)
  end

  def refusal_for(profile)
    I18n.t("npn_submissions.errors.unsupported_colour_profile", profile: profile)
  end

  it "refuses a ProPhoto JPEG and names the profile" do
    upload = upload_fixture("prophoto.jpg")

    expect(upload).not_to be_persisted
    expect(upload.errors.full_messages).to contain_exactly(refusal_for("ProPhoto RGB"))
  end

  it "refuses a ProPhoto PNG" do
    upload = upload_fixture("prophoto.png")

    expect(upload).not_to be_persisted
    expect(upload.errors.full_messages).to contain_exactly(refusal_for("ProPhoto RGB"))
  end

  it "refuses a profile it does not recognise" do
    upload = upload_fixture("unrecognised.jpg")

    expect(upload).not_to be_persisted
    expect(upload.errors.full_messages).to contain_exactly(refusal_for("Generic RGB Profile"))
  end

  it "accepts sRGB, Adobe RGB, Display P3, unprofiled and grayscale images" do
    uploads =
      %w[srgb.jpg adobergb.jpg p3.jpg no_profile.jpg gray.jpg].map { |name| upload_fixture(name) }

    expect(uploads.flat_map { |upload| upload.errors.full_messages }).to be_empty
    expect(uploads).to all(be_persisted)
  end

  it "accepts a ProPhoto image when the setting is off" do
    SiteSetting.npn_submissions_block_unsupported_colour_profiles = false

    expect(upload_fixture("prophoto.jpg")).to be_persisted
  end

  it "accepts a ProPhoto image when the plugin is disabled" do
    SiteSetting.npn_submissions_enabled = false

    expect(upload_fixture("prophoto.jpg")).to be_persisted
  end

  it "leaves uploads made without validation alone" do
    expect(upload_fixture("prophoto.jpg", { skip_validations: true })).to be_persisted
  end

  it "leaves an admin's site setting upload alone" do
    upload = upload_fixture("prophoto.jpg", { for_site_setting: true }, uploader: admin)

    expect(upload).to be_persisted
  end
end
