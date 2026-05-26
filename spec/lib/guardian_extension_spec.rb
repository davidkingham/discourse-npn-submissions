# frozen_string_literal: true

require "rails_helper"

# Managed-category composer blocking. The plugin prepends GuardianExtension onto
# Guardian to stop normal topic creation in managed categories for everyone
# except admins (the submission flow itself uses PostCreator with
# skip_guardian). These tests exercise the prepended Guardian, not the module in
# isolation, so they reflect real behaviour.
#
# Note: a plain fabricated user may not be permitted to create topics in core
# (trust-level / allowed-group gating), so "unaffected" cases are asserted as a
# baseline comparison (plugin off vs on) rather than an absolute true/false, and
# the "plugin is the blocker" case uses a moderator (staff), whom core allows.
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

    it "blocks moderators" do
      expect(can_create_topic?(moderator, managed_category)).to eq(false)
    end

    it "blocks regular users" do
      expect(can_create_topic?(user, managed_category)).to eq(false)
    end

    it "is the plugin enforcing the lock: a moderator allowed with the plugin off is blocked with it on" do
      SiteSetting.npn_submissions_enabled = false
      expect(can_create_topic?(moderator, managed_category)).to eq(true)

      SiteSetting.npn_submissions_enabled = true
      expect(can_create_topic?(moderator, managed_category)).to eq(false)
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

  describe "replies in a managed-category topic" do
    fab!(:managed_topic) { Fabricate(:topic, category: managed_category) }
    fab!(:managed_post) { Fabricate(:post, topic: managed_topic) }

    it "are still allowed for regular users (only new-topic creation is locked)" do
      expect(Guardian.new(user).can_create_post_on_topic?(managed_topic)).to eq(true)
    end
  end
end
