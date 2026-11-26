# frozen_string_literal: true

require "zlib"

module DiscourseNpnSubmissions
  # Reads the name of the ICC colour profile embedded in a JPEG, PNG or WebP
  # straight from the file, without ImageMagick. The Ruby twin of
  # assets/javascripts/discourse/lib/npn-colour-profile.js.
  #
  # The name sits in the first few kilobytes of the file, so reading it
  # directly is cheap and needs no image library (core's image tooling is
  # sandboxed and does not expose profile names).
  #
  # Never raises: missing, truncated or malformed input reads as no profile.
  module IccProfile
    # Enough to cover the metadata blocks that precede the profile in a JPEG.
    HEAD_BYTES = 1024 * 1024
    MAX_NAME_LENGTH = 60

    # Profile names that upload without complaint. Keep in step with ACCEPTED
    # in assets/javascripts/discourse/lib/npn-colour-profile.js, which gives
    # the member the same answer before the file is sent.
    #   sRGB:       "sRGB IEC61966-2.1", "sRGB built-in", "TINYsRGB", "Nikon
    #               sRGB 4.0.0.3001", and the compact "c2" some exporters embed
    #   Adobe RGB:  "Adobe RGB (1998)", "Nikon Adobe RGB 4.0.0.3001"
    #   Display P3: "Display P3", "Apple Wide Color Sharing Profile"
    ACCEPTED = /srgb|\Ac2\z|adobe\s*rgb|display\s*p3|apple wide color/i

    # True for no profile, a grayscale profile, or one of the ACCEPTED names.
    # `profile` is what `read` returns.
    def self.accepted?(profile)
      profile.nil? || profile[:space] == "GRAY" || profile[:name].match?(ACCEPTED)
    end

    # { name: "ProPhoto RGB", space: "RGB" }, or nil when there is no
    # readable profile.
    def self.read(path)
      head = File.binread(path, HEAD_BYTES)
      return nil if head.blank?

      profile =
        if head.start_with?("\xFF\xD8".b)
          jpeg_profile(head)
        elsif head.start_with?("\x89PNG".b)
          png_profile(head)
        elsif head[0, 4] == "RIFF" && head[8, 4] == "WEBP"
          webp_profile(head)
        end
      parse(profile)
    rescue StandardError
      nil
    end

    def self.parse(profile)
      return nil if profile.nil? || profile.bytesize < 132

      space = profile[16, 4].to_s.strip
      tag_count = profile[128, 4].unpack1("N")
      tag_count.times do |index|
        signature, offset = profile[132 + index * 12, 8].to_s.unpack("a4N")
        return nil if signature.nil?
        next if signature != "desc"

        name = description(profile, offset)
        return name.present? ? { name: name[0, MAX_NAME_LENGTH], space: space } : nil
      end
      nil
    end

    def self.description(profile, offset)
      text =
        case profile[offset, 4]
        when "desc"
          # ICC v2: a length-prefixed ASCII string.
          profile[offset + 12, profile[offset + 8, 4].unpack1("N")]
        when "mluc"
          # ICC v4: localised UTF-16BE strings; the first record is enough.
          length, start = profile[offset + 20, 8].unpack("NN")
          profile[offset + start, length]&.force_encoding(Encoding::UTF_16BE)&.encode(
            Encoding::UTF_8,
            invalid: :replace,
            undef: :replace,
          )
        end
      text&.scrub("")&.delete("\0")&.strip
    end

    def self.jpeg_profile(head)
      chunks = []
      offset = 2
      while offset + 4 <= head.bytesize
        return nil if head.getbyte(offset) != 0xFF

        marker = head.getbyte(offset + 1)
        break if marker == 0xDA || marker == 0xD9

        length = head[offset + 2, 2].unpack1("n")
        if marker == 0xE2 && head[offset + 4, 11] == "ICC_PROFILE"
          chunks << [head.getbyte(offset + 16), head[offset + 18, length - 16]]
        end
        offset += 2 + length
      end
      chunks.empty? ? nil : chunks.sort_by(&:first).map(&:last).join
    end

    def self.png_profile(head)
      offset = 8
      while offset + 8 <= head.bytesize
        length, type = head[offset, 8].unpack("Na4")
        return nil if %w[IDAT IEND].include?(type)

        if type == "iCCP"
          data = head[offset + 8, length]
          # Profile name, a zero byte, the compression method, then zlib data.
          return Zlib::Inflate.inflate(data[(data.index("\0") + 2)..])
        end
        offset += 12 + length
      end
      nil
    end

    def self.webp_profile(head)
      offset = 12
      while offset + 8 <= head.bytesize
        type, length = head[offset, 8].unpack("a4V")
        return head[offset + 8, length] if type == "ICCP"

        offset += 8 + length + (length % 2)
      end
      nil
    end
  end
end
