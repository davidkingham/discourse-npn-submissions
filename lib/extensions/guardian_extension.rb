# frozen_string_literal: true

module DiscourseNpnSubmissions
  module GuardianExtension
    # Block normal topic creation in managed categories for everyone except
    # admins. The plugin's submission service performs its own authorisation
    # checks and calls PostCreator with skip_guardian: true; this guard
    # applies to all other code paths (composer, API, automations).
    def can_create_topic_on_category?(category)
      return super unless DiscourseNpnSubmissions::Policy.enabled?
      return super unless category
      return super unless DiscourseNpnSubmissions::Policy.managed_category?(category)
      return true if DiscourseNpnSubmissions::Policy.bypasses_managed_category_lock?(@user)
      false
    end
  end
end
