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

    # Independent schema marker for the image-version metadata block — read by
    # the upcoming `discourse-revised-critique-image` and
    # `discourse-npn-critique-reply` plugins. Bumped separately from
    # SCHEMA_VERSION so revising image-metadata semantics doesn't churn the
    # rest of the metadata bag (and vice versa).
    CRITIQUE_IMAGE_VERSION_SCHEMA = 1

    # Schema version embedded inside the npn_project_submission_data JSON.
    # Independent of SCHEMA_VERSION and CRITIQUE_IMAGE_VERSION_SCHEMA so the
    # structured project payload can evolve on its own timeline. The future
    # project-revision plugin reads this before consuming the rest of the
    # payload.
    PROJECT_SUBMISSION_DATA_VERSION = 1

    # --- Custom field keys -----------------------------------------------------
    SCHEMA_VERSION_KEY = "npn_submission_schema_version"
    SUBMISSION_TYPE_KEY = "npn_submission_type"
    CRITIQUE_STYLE_KEY = "npn_critique_style"
    FEEDBACK_FOCUS_KEY = "npn_feedback_focus"
    WP_CHALLENGE_ID_KEY = "npn_wordpress_challenge_id"
    WEEKLY_CHALLENGE_TITLE_KEY = "npn_weekly_challenge_title"
    WEEKLY_CHALLENGE_DATES_KEY = "npn_weekly_challenge_dates"
    WP_CHALLENGE_URL_KEY = "npn_wordpress_challenge_url"

    # Photographer's opt-out for receiving processing examples from other
    # members. Stored only for the critique types whose form offers the
    # choice (see Submission::PROCESSING_EXAMPLE_OPT_OUT_TYPES). Read by
    # discourse-npn-critique-reply to show/hide its Processing Example
    # controls. A MISSING key means "allowed" — readers must default true.
    PROCESSING_EXAMPLES_ALLOWED_KEY = "npn_processing_examples_allowed"

    # Original (submitted) image references. The "original" prefix is
    # deliberate — a sibling plugin will add `npn_revised_*` keys for
    # post-feedback revisions, and the critique reply plugin needs to tell
    # them apart cleanly. This plugin owns only the originals.
    CRITIQUE_IMAGE_VERSION_SCHEMA_KEY = "npn_critique_image_version_schema"
    ORIGINAL_PRIMARY_UPLOAD_ID_KEY = "npn_original_primary_image_upload_id"
    ORIGINAL_PRIMARY_URL_KEY = "npn_original_primary_image_url"
    ORIGINAL_UPLOAD_IDS_KEY = "npn_original_image_upload_ids"
    ORIGINAL_IMAGE_COUNT_KEY = "npn_original_image_count"

    # Structured payload describing a project critique submission's images —
    # the source of truth for the future project-revision plugin. Written
    # only for `submission_type=project` with `method=images`; PDF/URL
    # projects have no image grid to describe.
    #
    # The post body's Project Overview grid + Image Sequence are display
    # output derived from the same `image_entries`, but downstream plugins
    # should read THIS field instead of parsing post HTML — `id` here is a
    # stable slot identifier that survives a future image-swap revision,
    # which positional parsing of the post cannot guarantee.
    PROJECT_SUBMISSION_DATA_KEY = "npn_project_submission_data"

    INTEGER_FIELDS = [
      SCHEMA_VERSION_KEY,
      WP_CHALLENGE_ID_KEY,
      CRITIQUE_IMAGE_VERSION_SCHEMA_KEY,
      ORIGINAL_PRIMARY_UPLOAD_ID_KEY,
      ORIGINAL_IMAGE_COUNT_KEY,
    ].freeze
    STRING_FIELDS = [
      SUBMISSION_TYPE_KEY,
      CRITIQUE_STYLE_KEY,
      FEEDBACK_FOCUS_KEY,
      WEEKLY_CHALLENGE_TITLE_KEY,
      WEEKLY_CHALLENGE_DATES_KEY,
      WP_CHALLENGE_URL_KEY,
      ORIGINAL_PRIMARY_URL_KEY,
    ].freeze
    # Order-preserving array of upload IDs. Stored via the `:json` custom
    # field type so readers get back a real Array (the legacy array-of-string
    # custom-field shape is deprecated in current Discourse).
    JSON_FIELDS = [ORIGINAL_UPLOAD_IDS_KEY, PROJECT_SUBMISSION_DATA_KEY].freeze
    # Registered with the `:boolean` custom field type so readers get back a
    # real true/false. Pre-encoded to "t"/"f" on write (see .save) because
    # upsert_custom_fields stores values raw.
    BOOLEAN_FIELDS = [PROCESSING_EXAMPLES_ALLOWED_KEY].freeze

    # --- Normalized enum maps --------------------------------------------------
    # Internal submission_type → public, stable identifier. Decouples future
    # readers from internal naming if we ever rename the internal enum.
    SUBMISSION_TYPE_MAP = {
      "image" => "image_critique",
      "weekly_challenge" => "weekly_challenge",
      "project" => "project_critique",
      "introduction" => "introduction",
      "new_member_image" => "new_member_image",
      "help" => "help",
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
    # Image URLs follow the same shape as WP_CHALLENGE_URL but live in a
    # separate constant so future tweaks (e.g. raising the cap for signed
    # S3/secure-media URLs) don't ripple through unrelated fields.
    MAX_IMAGE_URL = 500

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

      # Processing-examples opt-out. Written only for the critique types whose
      # form offers the choice; we deliberately DON'T write it for types that
      # never offered it (project critiques, onboarding posts) so readers can
      # cleanly treat a missing key as "allowed" rather than "explicitly off".
      if Submission::PROCESSING_EXAMPLE_OPT_OUT_TYPES.include?(submission.submission_type)
        meta[PROCESSING_EXAMPLES_ALLOWED_KEY] = submission.processing_examples_allowed?
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

      # Original submitted-image references. Best-effort: an unexpected
      # failure here (a corrupted Upload row, a store-config edge case)
      # is swallowed inside the helper so the schema/type/style/focus
      # fields above still reach the topic.
      add_original_image_metadata!(meta, submission)

      # Structured project payload (project critiques with the `images`
      # method only). Source of truth for the future project-revision
      # plugin; also best-effort so a per-image failure doesn't blank the
      # rest of the bag.
      add_project_submission_data!(meta, submission)

      meta
    end

    # Populate `meta` with references to the submission's original images, if
    # any. Keys are omitted (not stored as nil/blank) when there are no
    # surviving uploads — readers should treat missing keys as "this topic
    # has no original-image metadata", not "the original image is unknown".
    #
    # Reads `submission.image_entries`, which already preserves submission
    # order and drops duplicate upload IDs / missing uploads. The explicit
    # `.uniq` below is belt-and-suspenders so the contract documented on the
    # custom field ("no duplicates, order preserved") is enforced here, too.
    def add_original_image_metadata!(meta, submission)
      # Only image-critique submissions get the original-image refs custom
      # fields. That's the three critique types plus New Members Area images —
      # a new-member image is annotated in the critique workspace, so it needs
      # its original-image reference on the image-version surface even though it
      # isn't a full critique. Introduction has no annotatable image and stays
      # off. Using the enum so any future type is classified in one place.
      type = submission&.submission_type
      return if Submission::IMAGE_VERSION_TYPES.exclude?(type)

      uploads = original_uploads_for(submission)
      return if uploads.empty?

      ids = uploads.map(&:id).reject { |id| id.nil? || id.zero? }.uniq
      return if ids.empty?

      primary = uploads.first

      meta[CRITIQUE_IMAGE_VERSION_SCHEMA_KEY] = CRITIQUE_IMAGE_VERSION_SCHEMA
      meta[ORIGINAL_PRIMARY_UPLOAD_ID_KEY] = primary.id
      if (url = clean_string(stable_upload_url(primary), MAX_IMAGE_URL))
        meta[ORIGINAL_PRIMARY_URL_KEY] = url
      end
      meta[ORIGINAL_UPLOAD_IDS_KEY] = ids
      meta[ORIGINAL_IMAGE_COUNT_KEY] = ids.size
    rescue => e
      # If something goes wrong reading images (corrupted Upload row, store
      # config quirk, unexpected nil), keep the rest of the metadata bag
      # intact. The submission still has the uploads attached via
      # SubmissionUpload rows, so this is recoverable later if needed.
      Discourse.warn_exception(
        e,
        message:
          "[discourse-npn-submissions] failed to build original image metadata for submission=#{submission&.id}",
      )
      nil
    end

    # Submission#image_entries already returns ordered, deduped, present-only
    # uploads for Image, Weekly Challenge, and Project submissions. Indirected
    # through a small helper so callers (and future test stubs) have a single
    # surface to override.
    def original_uploads_for(submission)
      return [] if submission.nil?
      Array(submission.image_entries).filter_map { |entry| entry[:upload] }
    end

    # Populate `meta` with the structured project payload — the source of
    # truth for the future project-revision plugin. Only written when:
    #   - the submission is a project critique, AND
    #   - the project method is `images` (PDF/URL projects have no image
    #     grid to describe).
    #
    # Each image gets an opaque `id` (`SecureRandom.hex(8)`) at submission
    # time that is independent of position and of the upload itself, so a
    # later revision can swap the underlying upload without losing the
    # slot's identity.
    def add_project_submission_data!(meta, submission)
      return unless submission&.project?
      return unless submission.project_method == "images"

      entries = Array(submission.image_entries)
      return if entries.empty?

      images =
        entries.each_with_index.map do |entry, index|
          upload = entry[:upload]
          position = index + 1
          {
            "id" => SecureRandom.hex(8),
            "position" => position,
            "upload_id" => upload.id,
            "short_url" => upload.short_url,
            "caption" => entry[:note].to_s,
            "alt" => "Image #{position}",
          }
        end

      meta[PROJECT_SUBMISSION_DATA_KEY] = {
        "type" => "project_critique",
        "version" => PROJECT_SUBMISSION_DATA_VERSION,
        "images" => images,
      }
    rescue => e
      Discourse.warn_exception(
        e,
        message:
          "[discourse-npn-submissions] failed to build project submission data for submission=#{submission&.id}",
      )
      nil
    end

    # Resolve the upload's frontend-ready URL. Uses Discourse.store.cdn_url
    # (matching UploadSerializer's `url` field) so the value is directly
    # usable as `<img src>` regardless of whether the site is on local
    # storage, S3, or a CDN. Trade-off: if the site's CDN/storage config
    # changes after this is stored, the URL may become stale — consumers
    # should treat ORIGINAL_PRIMARY_UPLOAD_ID_KEY as the durable source of
    # truth and re-resolve via `Upload.find` if needed.
    def stable_upload_url(upload)
      raw = upload&.url.to_s
      return nil if raw.blank?
      Discourse.store.cdn_url(raw).presence || raw
    rescue StandardError
      # Don't let a single bad URL drop the whole image-metadata block.
      upload&.url.presence
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
      #
      # `upsert_custom_fields` writes values raw — it doesn't run the
      # field-type encoders that `save_custom_fields` would. Arrays happen to
      # round-trip because `[1,2,3].to_s == "[1, 2, 3]"` is parseable as JSON,
      # but Hashes serialize with `=>` hash rockets which `JSON.parse` rejects,
      # and a raw `true`/`false` is ambiguous to the read-side `:boolean`
      # typecast. Pre-encode JSON_FIELDS to a JSON string and BOOLEAN_FIELDS to
      # "t"/"f" so the registered typecasts decode them back to real Ruby
      # objects.
      topic.upsert_custom_fields(encode_for_upsert(metadata))
    rescue => e
      Discourse.warn_exception(
        e,
        message: "[discourse-npn-submissions] failed to save topic metadata for topic=#{topic&.id}",
      )
      nil
    end

    # Encode values into the string form the registered custom-field typecasts
    # expect on read, since upsert_custom_fields stores values raw. JSON_FIELDS
    # become a JSON string and BOOLEAN_FIELDS become "t"/"f". Idempotent:
    # values already given as Strings are passed through untouched, so callers
    # can pre-encode and double-encoding is avoided.
    def encode_for_upsert(metadata)
      metadata.each_with_object({}) do |(key, value), out|
        out[key] = if JSON_FIELDS.include?(key) && !value.is_a?(String)
          value.to_json
        elsif BOOLEAN_FIELDS.include?(key) && !value.is_a?(String)
          value ? "t" : "f"
        else
          value
        end
      end
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
