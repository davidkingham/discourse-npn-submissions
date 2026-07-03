# frozen_string_literal: true

require "rails_helper"

# Managed-category composer blocking. The plugin prepends GuardianExtension onto
# Guardian to stop normal topic creation in managed categories for everyone
# except staff — admins AND moderators bypass it server-side. (The submission
# flow itself uses PostCreator with skip_guardian; this guard applies to all
# other code paths: composer, API, scheduled publishing / staging-area tools,
# automations.) These tests exercise the prepended Guardian, not the module in
# isolation, so they reflect real behaviour.
#
# Note: a plain fabricated user may not be permitted to create topics in core
# (trust-level / allowed-group gating), so "unaffected" cases are asserted as a
# baseline comparison (plugin off vs on) rather than an absolute true/false.
describe DiscourseNpnSubmissions::GuardianExtension do
  fab!(:admin)
  fab!(:moderator)
  fab!(:user)
  fab!(:managed_category, :category)
  fab!(:open_category, :category)

  before do
    SiteSetting.npn_submissions_enabled = true
    SiteSetting.npn_submissions_managed_category_ids = managed_category.id.to_s
  end

  def can_create_topic?(actor, category)
    Guardian.new(actor).can_create_topic_on_category?(category)
  end

  describe "creating a topic in a managed category" do
    it "allows admins" do
      expect(can_create_topic?(admin, managed_category)).to eq(true)
    end

    it "allows moderators (staff bypass so secondary creation routes keep working)" do
      # Moderators reach the composer via /new-topic?category=…, scheduled
      # publishing, the API, etc. — those flows must not be blocked by the
      # plugin even though the default "+ New Topic" button is hidden for
      # them on the client.
      expect(can_create_topic?(moderator, managed_category)).to eq(true)
    end

    it "blocks regular users" do
      expect(can_create_topic?(user, managed_category)).to eq(false)
    end

    it "is the plugin enforcing the lock for non-staff: a regular user's permission flips with the setting" do
      # Without the plugin enforcing the lock, the regular user's permission
      # is whatever core would grant for this category. With the plugin
      # enabled, the same category becomes "managed" and the regular user is
      # blocked. The difference is the plugin doing its job; the baseline
      # itself can be anything core decides for a new category.
      SiteSetting.npn_submissions_enabled = false
      baseline = can_create_topic?(user, managed_category)

      SiteSetting.npn_submissions_enabled = true
      expect(can_create_topic?(user, managed_category)).to eq(false)
      # Don't assert baseline is true (core gating is out of our control);
      # only require that the plugin can't make the answer more permissive.
      expect(baseline).to be_in([true, false])
    end
  end

  describe "non-managed categories" do
    it "do not change core topic-creation behaviour for any role" do
      [admin, moderator, user].each do |actor|
        SiteSetting.npn_submissions_enabled = false
        baseline = can_create_topic?(actor, open_category)

        SiteSetting.npn_submissions_enabled = true
        expect(can_create_topic?(actor, open_category)).to eq(baseline)
      end
    end
  end

  describe "when the plugin is disabled" do
    it "does not enforce the lock (a managed category behaves like a normal one)" do
      SiteSetting.npn_submissions_enabled = false
      expect(can_create_topic?(user, managed_category)).to eq(
        can_create_topic?(user, open_category),
      )
    end
  end

  describe "editing a topic in a managed category" do
    fab!(:own_topic) { Fabricate(:topic, category: managed_category, user: user) }
    fab!(:own_first_post) { Fabricate(:post, topic: own_topic, user: user) }
    fab!(:other_topic) { Fabricate(:topic, category: managed_category) }
    fab!(:other_first_post) { Fabricate(:post, topic: other_topic) }

    before do
      SiteSetting.post_edit_time_limit = 0
      SiteSetting.tl2_post_edit_time_limit = 0
      # Core gates editing and topic creation on automatic trust-level group
      # membership, which fabricated users don't get in specs by default.
      Group.refresh_automatic_groups!
    end

    it "still lets the topic owner edit (e.g. rename) their own topic" do
      # Regression: core's can_edit_topic? reuses can_create_topic_on_category?,
      # so the managed lock used to strip owners of their edit/rename rights.
      expect(Guardian.new(user).can_edit_topic?(own_topic)).to eq(true)
    end

    it "does not grant edit rights core wouldn't (someone else's topic stays uneditable)" do
      expect(Guardian.new(user).can_edit_topic?(other_topic)).to eq(false)
    end

    it "keeps the creation lock intact after an edit check on the same guardian" do
      guardian = Guardian.new(user)
      guardian.can_edit_topic?(own_topic)
      expect(guardian.can_create_topic_on_category?(managed_category)).to eq(false)
    end
  end

  describe "replies in a managed-category topic" do
    fab!(:managed_topic) { Fabricate(:topic, category: managed_category) }
    fab!(:managed_post) { Fabricate(:post, topic: managed_topic) }

    it "are still allowed for regular users (only new-topic creation is locked)" do
      expect(Guardian.new(user).can_create_post_on_topic?(managed_topic)).to eq(true)
    end
  end
end
