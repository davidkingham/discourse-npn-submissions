# frozen_string_literal: true

module DiscourseNpnSubmissions
  # Converts uploaded photographs that carry a non-sRGB ICC profile
  # (ProPhoto RGB, Adobe RGB, Display P3, a monitor profile…) to sRGB before
  # the upload is stored.
  #
  # Why: Discourse's resized copies (what a post shows inline) are always
  # converted to sRGB, but the original file is served untouched to the
  # lightbox, the critique workspace and downloads. A ProPhoto original is
  # rendered noticeably differently from its sRGB copy by browsers (warmer
  # on a toned black-and-white, for example), so critics end up comparing
  # two versions of the same photograph. Converting the original once on
  # upload makes every view show the same colours.
  #
  # Hooks into UploadCreator's orientation step: it is the one point in
  # `create_for` that runs before the file's SHA1, size and dimensions are
  # recorded, and it already rewrites the original in place. The core
  # orientation fix still runs exactly when it did before.
  #
  # Conversion uses relative colorimetric with black-point compensation —
  # Photoshop's default for Convert to Profile — against the same sRGB
  # profile core uses for its resized copies. Grayscale images are left
  # alone (browsers render gray profiles consistently), as are images with
  # no profile, GIFs and anything animated.
  module SrgbUploadExtension
    CONVERTIBLE_TYPES = %w[jpeg jpg png webp].freeze
    # Descriptions of sRGB profiles in the wild: "sRGB IEC61966-2.1",
    # "sRGB built-in", "sRGB v4 ICC preference", "TINYsRGB", and the
    # compact "c2" profile some exporters embed.
    SRGB_DESCRIPTION = /srgb|\Ac2\z/i
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

      !description.match?(SRGB_DESCRIPTION)
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
