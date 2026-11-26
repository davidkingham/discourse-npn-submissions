# frozen_string_literal: true

module DiscourseNpnSubmissions
  # Converts uploaded photographs in ProPhoto RGB, or in a profile we don't
  # recognise (a monitor profile, a camera or scanner profile…), to sRGB
  # before the upload is stored. sRGB, Adobe RGB and Display P3 are left
  # alone.
  #
  # Why: Discourse's resized copies (what a post shows inline) are always
  # converted to sRGB, but the original file is served untouched to the
  # lightbox, the critique workspace and downloads. For an 8-bit ProPhoto
  # JPEG those two do not look the same. Photoshop and ImageMagick round the
  # JPEG to 8-bit ProPhoto pixels and then convert; browsers convert from the
  # unrounded data. ProPhoto's primaries are so wide that the rounding is
  # visible: on a toned black-and-white (topic 53175) Chrome and Safari's
  # engine drew the original 1 to 2 dE2000 redder than Photoshop did, while
  # the resized copy matched Photoshop. Converting the original on upload
  # makes every view show what the photographer saw in Photoshop.
  #
  # Adobe RGB and Display P3 are much narrower, browsers render them the
  # same as Photoshop on the same pixels, and converting them would throw
  # away colour that wide-gamut screens can show, so they are not touched.
  #
  # Hooks into UploadCreator's orientation step: it is the one point in
  # `create_for` that runs before the file's SHA1, size and dimensions are
  # recorded, and it already rewrites the original in place. The core
  # orientation fix still runs exactly when it did before.
  #
  # Conversion uses relative colorimetric with black-point compensation —
  # Photoshop's default for Convert to Profile — against the same sRGB
  # profile core uses for its resized copies; the result matched
  # Photoshop's own conversion to within 0.01 dE2000. Grayscale images are
  # left alone (browsers render gray profiles consistently), as are images
  # with no profile, GIFs and anything animated.
  module SrgbUploadExtension
    CONVERTIBLE_TYPES = %w[jpeg jpg png webp].freeze
    # Profile descriptions that are left alone. Keep in step with
    # LEFT_ALONE in assets/javascripts/discourse/lib/npn-colour-profile.js,
    # which decides when the form warns the photographer.
    #   sRGB:       "sRGB IEC61966-2.1", "sRGB built-in", "TINYsRGB", "Nikon
    #               sRGB 4.0.0.3001", and the compact "c2" some exporters embed
    #   Adobe RGB:  "Adobe RGB (1998)", "Nikon Adobe RGB 4.0.0.3001"
    #   Display P3: "Display P3", "Apple Wide Color Sharing Profile"
    LEFT_ALONE = /srgb|\Ac2\z|adobe\s*rgb|display\s*p3|apple wide color/i
    IDENTIFY_TIMEOUT = 10
    CONVERT_TIMEOUT = 30

    def should_fix_orientation?
      super || npn_needs_srgb_conversion?
    end

    def fix_orientation!
      super if @image_info.orientation.to_i > 1
      npn_convert_to_srgb! if npn_needs_srgb_conversion?
    end

    private

    # The sRGB profile core uses for its resized copies.
    def npn_srgb_profile_path
      Rails.root.join("vendor/data/RT_sRGB.icm").to_s
    end

    def npn_needs_srgb_conversion?
      return false if @npn_srgb_done
      return false unless SiteSetting.npn_submissions_enabled
      return false unless SiteSetting.npn_submissions_convert_uploads_to_srgb
      return false if @opts[:for_theme] || @opts[:for_export] || @opts[:for_site_setting]
      return false if CONVERTIBLE_TYPES.exclude?(@image_info&.type.to_s)
      return false if animated?

      colorspace, description = npn_color_info
      return false if description.blank?
      return false if colorspace.to_s.casecmp?("gray")

      !description.match?(LEFT_ALONE)
    end

    # [colorspace, icc_description], read once per upload. An unreadable
    # file reports no profile, which leaves it untouched.
    def npn_color_info
      @npn_color_info ||=
        begin
          OptimizedImage.ensure_safe_paths!(@file.path)
          source =
            OptimizedImage.prepend_decoder!(
              @file.path,
              nil,
              filename: "image.#{@image_info.type}",
            )
          Discourse::Utils
            .execute_command(
              "magick",
              "identify",
              "-ping",
              "-format",
              "%[colorspace]|%[profile:icc]",
              "#{source}[0]",
              timeout: IDENTIFY_TIMEOUT,
            )
            .to_s
            .strip
            .split("|", 2)
        rescue StandardError => e
          Rails.logger.warn("[npn-submissions] sRGB check failed: #{e.class}: #{e.message}")
          [nil, nil]
        end
    end

    def npn_convert_to_srgb!
      @npn_srgb_done = true
      type = @image_info.type.to_s
      path = @file.path
      tmp = "#{path}.npn-srgb.#{type}"

      OptimizedImage.ensure_safe_paths!(path, tmp)
      source = OptimizedImage.prepend_decoder!(path, nil, filename: "image.#{type}")
      target = OptimizedImage.prepend_decoder!(tmp)

      Discourse::Utils.execute_command(
        "magick",
        source,
        "-intent",
        "Relative",
        "-black-point-compensation",
        "-profile",
        npn_srgb_profile_path,
        target,
        timeout: CONVERT_TIMEOUT,
      )

      # Copy the result back into the original file rather than moving it:
      # UploadCreator still holds an open handle on @file, so the bytes have
      # to change under the same inode.
      File.open(path, "wb") { |out| File.open(tmp, "rb") { |src| IO.copy_stream(src, out) } }
      @file.rewind
      extract_image_info!
    rescue StandardError => e
      # Never block an upload over this: on any failure the original is
      # stored unconverted, exactly as before this extension existed.
      Rails.logger.warn("[npn-submissions] sRGB conversion failed: #{e.class}: #{e.message}")
    ensure
      FileUtils.rm_f(tmp) if tmp
    end
  end
end
