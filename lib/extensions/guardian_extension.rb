# frozen_string_literal: true

module DiscourseNpnSubmissions
  module GuardianExtension
    # Block normal topic creation in managed categories for everyone except
    # staff (admins + moderators). The plugin's submission service performs
    # its own authorisation checks and calls PostCreator with
    # skip_guardian: true; this guard applies to all other code paths
    # (composer, API, automations). Moderators bypass the server-side
    # block so secondary creation routes — `/new-topic?category=…`,
    # scheduled-publishing / staging-area flows, the API — keep working
    # for them; the default "+ New Topic" button is still hidden for them
    # client-side so they're nudged toward the structured submission form
    # by default.
    # Core's `can_edit_topic?` reuses `can_create_topic_on_category?` to bar
    # edits in categories where the user can't create topics. The managed
    # lock must not inherit that behaviour — members own their submission
    # topics and may rename them — so the lock is suspended while an edit
    # check is being evaluated.
    def can_edit_topic?(topic)
      @npn_skip_managed_category_lock = true
      super
    ensure
      @npn_skip_managed_category_lock = nil
    end

    def can_create_topic_on_category?(category)
      return super if @npn_skip_managed_category_lock
      return super unless DiscourseNpnSubmissions::Policy.enabled?
      return super unless category
      return super unless DiscourseNpnSubmissions::Policy.managed_category?(category)
      return true if DiscourseNpnSubmissions::Policy.bypasses_managed_category_lock?(@user)
      false
    end
  end
end
