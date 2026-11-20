# frozen_string_literal: true

module DiscourseNpnSubmissions
  # The photographer's hang for an image-method project: how the prints are
  # laid out on the wall, the wall / mat / frame look, and each print's size.
  # Authored in the project form ("Hang your show"), stored in the
  # submission's `data["hang"]`, and served with `npn_project_images` so the
  # exhibition wall shows exactly this hang.
  #
  # Sizes are real: each print's LONG edge in inches, keyed by upload id (so a
  # size follows its print when the photographer reorders). The short edge
  # follows the image's proportions. Everything is normalized here so the
  # client can trust the shape and old/garbled data falls back to defaults.
  module ProjectHang
    LAYOUTS = %w[line rows lead].freeze
    WALLS = %w[warm gray charcoal].freeze
    MATS = %w[none white offwhite black].freeze
    FRAMES = %w[none black wood white].freeze
    UNITS = %w[in cm].freeze
    MAT_WIDTHS = [2, 3, 4].freeze # inches
    # Standard print long edges (inches) the size grip snaps to.
    PRINT_SIZES = [8, 10, 12, 14, 16, 20, 24, 30, 36, 40, 48, 60].freeze
    DEFAULT_PRINT_SIZE = 20
    # A book: the page shape, and for each spread one image (on the left
    # page, the right page, or across both) or two facing images. `cover` is
    # the upload used on the cover (a project image or an alternate).
    BOOK_FORMATS = %w[portrait square landscape].freeze
    SPREAD_SIDES = %w[right left full].freeze
    MAX_SPREADS = 60

    module_function

    # => { layout:, wall:, mat:, mat_width:, frame:, unit:, sizes: { "id" => in } }
    #    or nil when the submission never set a hang.
    def from_submission(submission)
      raw = submission&.data&.[]("hang")
      return nil unless raw.is_a?(Hash)
      normalize(raw)
    end

    def normalize(raw)
      raw = raw.to_h.stringify_keys
      {
        layout: pick(raw["layout"], LAYOUTS),
        wall: pick(raw["wall"], WALLS),
        mat: pick(raw["mat"], MATS),
        mat_width: MAT_WIDTHS.include?(raw["mat_width"].to_i) ? raw["mat_width"].to_i : nil,
        frame: pick(raw["frame"], FRAMES),
        unit: pick(raw["unit"], UNITS) || "in",
        sizes: normalize_sizes(raw["sizes"]),
        book_format: pick(raw["book_format"], BOOK_FORMATS),
        cover: raw["cover"].to_i.positive? ? raw["cover"].to_i : nil,
        spreads: normalize_spreads(raw["spreads"]),
      }.compact
    end

    # Unknown values become nil (the client fills in the goal's default).
    def pick(value, allowed)
      value = value.to_s
      allowed.include?(value) ? value : nil
    end

    def normalize_sizes(raw)
      return {} unless raw.is_a?(Hash)
      raw.each_with_object({}) do |(key, value), out|
        id = key.to_s
        size = value.to_i
        out[id] = size if id.match?(/\A\d+\z/) && PRINT_SIZES.include?(size)
      end
    end

    # [{ ids: [upload_id] , side: "right" } | { ids: [id, id] }], or nil when
    # there are none (so hangs for other goals don't carry an empty list).
    def normalize_spreads(raw)
      return nil unless raw.is_a?(Array)
      spreads =
        raw
          .first(MAX_SPREADS)
          .filter_map do |spread|
            spread = spread.to_h.stringify_keys if spread.respond_to?(:to_h)
            next unless spread.is_a?(Hash)
            ids = Array(spread["ids"]).map(&:to_i).select(&:positive?).first(2)
            next if ids.empty?
            if ids.size == 2
              { ids: ids }
            else
              { ids: ids, side: pick(spread["side"], SPREAD_SIDES) || "right" }
            end
          end
      spreads.presence
    end

    # A print's long edge in inches for an upload, or nil (client default).
    def print_size(hang, upload_id)
      hang&.dig(:sizes, upload_id.to_s)
    end
  end
end
