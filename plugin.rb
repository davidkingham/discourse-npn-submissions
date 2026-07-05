# frozen_string_literal: true

# name: discourse-npn-submissions
# about: Modern submission flows for Nature Photographers Network critique content.
# version: 0.1.0
# authors: David Kingham
# url: https://github.com/davidkingham/discourse-npn-submissions
# license: MIT

enabled_site_setting :npn_submissions_enabled

register_asset "stylesheets/npn-submissions.scss"

register_svg_icon "camera"
register_svg_icon "image"
register_svg_icon "trash-can"
register_svg_icon "arrow-up"
register_svg_icon "arrow-down"
register_svg_icon "grip-lines"
register_svg_icon "cloud-arrow-up"
register_svg_icon "link"
register_svg_icon "triangle-exclamation"

module ::DiscourseNpnSubmissions
  PLUGIN_NAME = "discourse-npn-submissions"
end

require_relative "lib/discourse_npn_submissions/engine"

add_admin_route "npn_submissions.admin.title", "npn-submissions"

after_initialize do
  require_relative "app/models/discourse_npn_submissions/submission"
  require_relative "app/models/discourse_npn_submissions/submission_upload"
  require_relative "lib/discourse_npn_submissions/policy"
  require_relative "lib/discourse_npn_submissions/daily_limit"
  require_relative "lib/discourse_npn_submissions/weekly_challenge_info"
  require_relative "lib/discourse_npn_submissions/post_builder"
  require_relative "lib/discourse_npn_submissions/project_post_builder"
  require_relative "lib/discourse_npn_submissions/introduction_post_builder"
  require_relative "lib/discourse_npn_submissions/new_member_image_post_builder"
  require_relative "lib/discourse_npn_submissions/help_post_builder"
  require_relative "lib/discourse_npn_submissions/draft_store"
  require_relative "lib/discourse_npn_submissions/topic_metadata"
  require_relative "lib/discourse_npn_submissions/submitter"
  require_relative "lib/extensions/guardian_extension"
  require_relative "app/serializers/discourse_npn_submissions/submission_serializer"
  require_relative "app/serializers/discourse_npn_submissions/admin_submission_serializer"
  require_relative "app/controllers/discourse_npn_submissions/submissions_controller"
  require_relative "app/controllers/discourse_npn_submissions/drafts_controller"
  require_relative "app/controllers/discourse_npn_submissions/admin/submissions_controller"

  reloadable_patch { |plugin| Guardian.prepend(DiscourseNpnSubmissions::GuardianExtension) }

  # Register the topic custom fields we attach to successfully created
  # submissions so they typecast correctly on read. See TopicMetadata for the
  # rationale (durable, forward-looking signal for future plugins/features).
  DiscourseNpnSubmissions::TopicMetadata::INTEGER_FIELDS.each do |key|
    Topic.register_custom_field_type(key, :integer)
  end
  DiscourseNpnSubmissions::TopicMetadata::STRING_FIELDS.each do |key|
    Topic.register_custom_field_type(key, :string)
  end
  # :json gives us back a real Array on read, which is what the critique
  # reply plugin expects for the original image upload-id list. (The legacy
  # array-of-string custom-field shape is deprecated in current Discourse.)
  DiscourseNpnSubmissions::TopicMetadata::JSON_FIELDS.each do |key|
    Topic.register_custom_field_type(key, :json)
  end
  # :boolean gives us back a real true/false on read for the processing-
  # examples opt-out the critique reply plugin consumes.
  DiscourseNpnSubmissions::TopicMetadata::BOOLEAN_FIELDS.each do |key|
    Topic.register_custom_field_type(key, :boolean)
  end

  add_to_serializer(:current_user, :can_npn_submit) do
    DiscourseNpnSubmissions::Policy.can_submit?(object)
  end

  # Expose the photographer's processing-examples preference on topic view so
  # discourse-npn-critique-reply can show/hide its Processing Example controls
  # without re-reading custom fields. Missing — older critique topics, or
  # types that never offered the choice — is treated as allowed (true).
  add_to_serializer(:topic_view, :npn_processing_examples_allowed) do
    raw =
      object.topic.custom_fields[
        DiscourseNpnSubmissions::TopicMetadata::PROCESSING_EXAMPLES_ALLOWED_KEY
      ]
    raw.nil? ? true : raw
  end

  # Expose the photographer's STRUCTURED request/narrative fields on topic
  # view, sourced live from the submission row (the source of truth) — NOT
  # duplicated into topic custom fields, honoring TopicMetadata's "no
  # freeform text in custom fields" contract. discourse-npn-critique-reply
  # consumes these to pin the "Feedback Requested" ask above the critique
  # field and to build its Photographer's Notes panel from structured
  # sections instead of parsing the cooked OP body.
  #
  # Read-only and cheap: ONE memoized row lookup per topic view, and only
  # for topics that are actually submissions (gated on the preloaded
  # `npn_submission_type` custom field, so non-submission topics never
  # touch the DB). Values are the raw markdown the photographer authored;
  # the client cooks/sanitizes them through Discourse's pipeline for
  # display. nil when there is no submission row (pre-plugin / imported /
  # hand-authored topics) or the optional field was left blank.
  module ::DiscourseNpnSubmissions
    module TopicViewSerializerExtension
      # Memoized so every npn_* narrative attribute below shares ONE query.
      # `defined?` guard caches a nil result too (no re-query for
      # non-submission topics).
      def npn_submission_row
        return @npn_submission_row if defined?(@npn_submission_row)

        @npn_submission_row =
          if object
               .topic
               &.custom_fields
               &.[](DiscourseNpnSubmissions::TopicMetadata::SUBMISSION_TYPE_KEY)
               .present?
            DiscourseNpnSubmissions::Submission.find_by(topic_id: object.topic.id)
          end
      end
    end
  end
  reloadable_patch do |_plugin|
    TopicViewSerializer.prepend(DiscourseNpnSubmissions::TopicViewSerializerExtension)
  end

  # Serialized attribute → submission `data.fields.<key>`. The ask lives
  # under `feedback_requested` for BOTH standard and in-depth styles (the
  # OP post merely re-heads it to "Where Feedback Would Help Most" for
  # in-depth); reaction style has no `feedback_requested` — its ask is
  # `questions_for_viewers`.
  {
    npn_about_this_image: "about_this_image",
    npn_technical_details: "technical_details",
    npn_creative_intent: "creative_intent",
    npn_creative_direction: "creative_direction",
    npn_questions_for_viewers: "questions_for_viewers",
    npn_feedback_after: "feedback_after",
  }.each do |attr, field_key|
    add_to_serializer(
      :topic_view,
      attr,
      include_condition: -> { npn_submission_row.present? },
      # `.presence` normalizes blank/absent optional fields to nil (the model
      # returns "" for a missing key) so the client gets a clean null rather
      # than an empty string.
    ) { npn_submission_row.field(field_key).presence }
  end

  # The photographer's "ask". Standard/in-depth store it under
  # `feedback_requested`; the New Members Area image form stores the same intent
  # under `feedback` (its heading is "Feedback Welcome", not "Feedback
  # Requested"). Fall back to `feedback` so the critique workspace's pinned ask
  # is populated for new-member images too. `feedback_requested` wins when both
  # exist, and no other type carries a `feedback` key, so the fallback only ever
  # fires for new-member images.
  add_to_serializer(
    :topic_view,
    :npn_feedback_requested,
    include_condition: -> { npn_submission_row.present? },
  ) do
    npn_submission_row.field("feedback_requested").presence ||
      npn_submission_row.field("feedback").presence
  end

  # Changing the WordPress endpoint should refetch, not keep serving the old
  # site's cached challenge.
  on(:site_setting_changed) do |name, _old_value, _new_value|
    if name == :npn_submissions_weekly_challenge_api_url
      DiscourseNpnSubmissions::WeeklyChallengeInfo.clear_cache
    end
  end

  Discourse::Application.routes.append { mount ::DiscourseNpnSubmissions::Engine, at: "/" }
end
