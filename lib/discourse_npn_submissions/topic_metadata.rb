# frozen_string_literal: true

module DiscourseNpnSubmissions
  # Builds and persists the small, normalized metadata bag we attach to a
  # successfully-created submission topic via Topic custom fields.
  #
  # Purpose: give future plugins/features (a guided critique-tools plugin, a
  # Weekly Challenge archive/filter view) a stable read-only signal for things
  # that aren't reliably available from native Discourse data — specifically
  # submission type, critique intent, and Weekly Challenge identity. This is
  # NOT a shadow database of the submission; freeform text, tags, image
  # counts, project method, etc. are deliberately not stored here (future
  # plugins can read tags/category/post content directly from Discourse).
  #
  # Contract:
  # - Only normalized, enum-mapped values are written. Unknown enum values are
  #   silently omitted rather than stored as noise.
  # - All string values are stripped and length-capped.
  # - .save NEVER raises — a metadata failure must not roll back or fail the
  #   surrounding topic creation. Failures are logged via Discourse.warn_exception.
  module TopicMetadata
    # Bump when the meaning of a stored field changes incompatibly. Readers in
    # future plugins should check this before consuming other keys.
    SCHEMA_VERSION = 1

    # --- Custom field keys -----------------------------------------------------
    SCHEMA_VERSION_KEY = "npn_submission_schema_version"
    SUBMISSION_TYPE_KEY = "npn_submission_type"
    CRITIQUE_STYLE_KEY = "npn_critique_style"
    FEEDBACK_FOCUS_KEY = "npn_feedback_focus"
    WP_CHALLENGE_ID_KEY = "npn_wordpress_challenge_id"
    WEEKLY_CHALLENGE_TITLE_KEY = "npn_weekly_challenge_title"
    WEEKLY_CHALLENGE_DATES_KEY = "npn_weekly_challenge_dates"
    WP_CHALLENGE_URL_KEY = "npn_wordpress_challenge_url"

    INTEGER_FIELDS = [SCHEMA_VERSION_KEY, WP_CHALLENGE_ID_KEY].freeze
    STRING_FIELDS = [
      SUBMISSION_TYPE_KEY,
      CRITIQUE_STYLE_KEY,
      FEEDBACK_FOCUS_KEY,
      WEEKLY_CHALLENGE_TITLE_KEY,
      WEEKLY_CHALLENGE_DATES_KEY,
      WP_CHALLENGE_URL_KEY,
    ].freeze

    # --- Normalized enum maps --------------------------------------------------
    # Internal submission_type → public, stable identifier. Decouples future
    # readers from internal naming if we ever rename the internal enum.
    SUBMISSION_TYPE_MAP = {
      "image" => "image_critique",
      "weekly_challenge" => "weekly_challenge",
      "project" => "project_critique",
    }.freeze

    CRITIQUE_STYLE_MAP = {
      "standard" => "standard",
      "in_depth" => "in_depth",
      "reaction" => "initial_reaction",
    }.freeze

    # Image / Weekly / Project all share the same internal FEEDBACK_FOCUSES enum
    # ("artistic" / "technical" / "both"), so this single map covers all three.
    FEEDBACK_FOCUS_MAP = {
      "artistic" => "artistic_expressive",
      "technical" => "technical_help",
      "both" => "artistic_technical",
    }.freeze

    # Length caps for stored strings; well below the 200-byte index limits that
    # Discourse custom-field tables tolerate and small enough not to bloat row
    # storage. Long values are trimmed, not rejected.
    MAX_TITLE = 200
    MAX_DATES = 100
    MAX_URL = 500

    module_function

    # Build the normalized metadata hash for `submission`. Returns a Hash of
    # custom_field_key => value with no nils, no empty strings, and no
    # unrecognised enum values. Keys absent from the hash should be absent from
    # the topic — readers should treat missing keys as "unknown", not "default".
    def build(submission)
      meta = { SCHEMA_VERSION_KEY => SCHEMA_VERSION }

      if (type = SUBMISSION_TYPE_MAP[submission.submission_type])
        meta[SUBMISSION_TYPE_KEY] = type
      end

      # critique_style is nil for project submissions — naturally omitted by the
      # map miss. We never store an unrecognised value.
      if (style = CRITIQUE_STYLE_MAP[submission.critique_style])
        meta[CRITIQUE_STYLE_KEY] = style
      end

      # Project's feedback_focus is structured under the same enum, so include
      # it for all three submission types. Unknown values omitted.
      if (focus = FEEDBACK_FOCUS_MAP[submission.feedback_focus])
        meta[FEEDBACK_FOCUS_KEY] = focus
      end

      # Weekly Challenge identity comes from the WordPress sync that the same
      # PostBuilder used to compose the post body, so if a value is present in
      # the post it is also present here (and vice versa). Missing values are
      # individually omitted.
      if submission.weekly_challenge?
        info = weekly_challenge_info
        if info.is_a?(Hash)
          meta[WP_CHALLENGE_ID_KEY] = info[:id] if info[:id].is_a?(Integer) && info[:id].positive?
          if (title = clean_string(info[:title], MAX_TITLE))
            meta[WEEKLY_CHALLENGE_TITLE_KEY] = title
          end
          if (dates = clean_string(info[:dates], MAX_DATES))
            meta[WEEKLY_CHALLENGE_DATES_KEY] = dates
          end
          if (url = clean_string(info[:url], MAX_URL))
            meta[WP_CHALLENGE_URL_KEY] = url
          end
        end
      end

      meta
    end

    # Apply `metadata` to `topic` as Discourse custom fields. Never raises:
    # any error (invalid topic, DB failure, etc.) is logged and swallowed so a
    # metadata failure can't roll back or fail the surrounding topic creation.
    def save(topic, metadata)
      return if topic.blank?
      return if metadata.blank?

      # upsert_custom_fields writes directly to topic_custom_fields. We use it
      # instead of `save_custom_fields` because the latter calls `topic.save`,
      # which re-runs full Topic validations (including DiscourseTagging's
      # "you're allowed to tag" check) — that fails for normal users on their
      # own newly-created topic and would silently drop our metadata.
      topic.upsert_custom_fields(metadata)
    rescue => e
      Discourse.warn_exception(
        e,
        message: "[discourse-npn-submissions] failed to save topic metadata for topic=#{topic&.id}",
      )
      nil
    end

    # Strip + length-cap a value down to a stored string, or nil if empty.
    def clean_string(value, max)
      return nil if value.nil?
      s = value.to_s.strip
      return nil if s.blank?
      s.length > max ? s[0, max].strip : s
    end

    # Indirection so tests can stub the sync result without reaching through
    # the controller layer.
    def weekly_challenge_info
      WeeklyChallengeInfo.current
    end
  end
end
