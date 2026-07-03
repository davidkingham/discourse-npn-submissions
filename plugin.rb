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

  # Changing the WordPress endpoint should refetch, not keep serving the old
  # site's cached challenge.
  on(:site_setting_changed) do |name, _old_value, _new_value|
    if name == :npn_submissions_weekly_challenge_api_url
      DiscourseNpnSubmissions::WeeklyChallengeInfo.clear_cache
    end
  end

  Discourse::Application.routes.append { mount ::DiscourseNpnSubmissions::Engine, at: "/" }
end
