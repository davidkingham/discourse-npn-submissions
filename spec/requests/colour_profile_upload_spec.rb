# frozen_string_literal: true

require "rails_helper"

describe "Uploading an image by its colour profile" do
  fab!(:user) { Fabricate(:user, refresh_auto_groups: true) }

  let(:fixtures) { File.expand_path("../fixtures/images", __dir__) }

  before do
    SiteSetting.npn_submissions_enabled = true
    sign_in(user)
  end

  def upload(name)
    post "/uploads.json",
         params: {
           file: Rack::Test::UploadedFile.new(File.join(fixtures, name), "image/jpeg"),
           upload_type: "composer",
         }
  end

  describe "POST /uploads.json" do
    it "refuses a ProPhoto image with a message naming the profile" do
      upload("prophoto.jpg")

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]).to contain_exactly(
        I18n.t("npn_submissions.errors.unsupported_colour_profile", profile: "ProPhoto RGB"),
      )
    end

    it "accepts an sRGB image" do
      upload("srgb.jpg")

      expect(response.status).to eq(200)
      expect(response.parsed_body["original_filename"]).to eq("srgb.jpg")
    end
  end
end
