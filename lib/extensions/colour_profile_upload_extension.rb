# frozen_string_literal: true

module DiscourseNpnSubmissions
  # Refuses image uploads whose embedded colour profile is not sRGB, Adobe RGB
  # or Display P3: ProPhoto RGB, monitor profiles, camera or scanner profiles,
  # CMYK and the like. The member is told which profile was found and asked to
  # export in sRGB.
  #
  # Why: those files do not look the same in every view. On an 8-bit ProPhoto
  # JPEG (topic 53175) Chrome drew the original about 1.4 dE2000 away from
  # Photoshop, and the resized copy core makes with libvips was about 1.4 away
  # in a different way, so the enlarged view, the post and what the
  # photographer saw in Photoshop were three different pictures. The same
  # photograph exported in sRGB matched across all three (within 0.5).
  # Converting on the server was tried and dropped: it re-saves the file and
  # still does not match Photoshop. An unfamiliar profile is almost always an
  # export mistake, so the photographer is asked to look again.
  #
  # Checked at the very start of `create_for`, on the file as uploaded, rather
  # than in the `before_upload_creation` event: by then core has optimised the
  # file, and with `strip_image_metadata` on the profile is already gone (the
  # image would then be stored untagged and shown with the wrong colours).
  # Refusing here also skips the image processing for a file we will not keep.
  module ColourProfileUploadExtension
    def create_for(user_id)
      rejected = npn_rejected_colour_profile
      if rejected
        @upload.errors.add(
          :base,
          I18n.t("npn_submissions.errors.unsupported_colour_profile", profile: rejected),
        )
        return @upload
      end

      super
    end

    private

    # The name of the profile that makes this upload unacceptable, or nil.
    def npn_rejected_colour_profile
      return if !SiteSetting.npn_submissions_enabled
      return if !SiteSetting.npn_submissions_block_unsupported_colour_profiles
      return if @opts[:validate] == false
      return if @opts[:for_theme] || @opts[:for_site_setting] || @opts[:for_export]
      return if @opts[:for_gravatar] || @opts[:external_upload_too_big]
      return if !@file.respond_to?(:path) || @file.path.blank?

      profile = IccProfile.read(@file.path)
      IccProfile.accepted?(profile) ? nil : profile[:name]
    end
  end
end
