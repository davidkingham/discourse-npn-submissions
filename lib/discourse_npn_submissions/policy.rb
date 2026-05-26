# frozen_string_literal: true

module DiscourseNpnSubmissions
  module Policy
    module_function

    def enabled?
      SiteSetting.npn_submissions_enabled
    end

    def managed_category_ids
      raw = SiteSetting.npn_submissions_managed_category_ids.to_s
      raw.split("|").map { |id| id.to_i }.reject(&:zero?)
    end

    def managed_category?(category_or_id)
      id =
        (
          if category_or_id.respond_to?(:id)
            category_or_id.id
          else
            category_or_id.to_i
          end
        )
      return false if id.zero?
      managed_category_ids.include?(id)
    end

    def allowed_group_ids
      SiteSetting
        .npn_submissions_allowed_groups
        .to_s
        .split("|")
        .map(&:to_i)
        .reject(&:zero?)
    end

    def in_allowed_group?(user)
      return false if user.blank?
      ids = allowed_group_ids
      return false if ids.empty?
      GroupUser.exists?(group_id: ids, user_id: user.id)
    end

    # Who may use the submission flows. Admins always; otherwise must be in
    # one of the configured groups.
    def can_submit?(user)
      return false if user.blank?
      return false unless enabled?
      return true if user.admin?
      in_allowed_group?(user)
    end

    # --- Descriptive tag constraint --------------------------------------------

    def descriptive_tag_group_names
      SiteSetting
        .npn_submissions_descriptive_tag_group
        .to_s
        .split("|")
        .map(&:strip)
        .reject(&:blank?)
    end

    def descriptive_tags_constrained?
      descriptive_tag_group_names.any?
    end

    # Tag names a submitter may use as descriptive tags, drawn from the
    # configured tag group(s). Empty when unconstrained (any existing tag is
    # allowed).
    def allowed_descriptive_tag_names
      groups = descriptive_tag_group_names
      return [] if groups.empty?

      Tag
        .joins(:tag_groups)
        .where(tag_groups: { name: groups })
        .distinct
        .pluck(:name)
    end

    # Admins bypass; moderators DO NOT bypass.
    def bypasses_daily_limit?(user)
      return false if user.blank?
      user.admin?
    end

    # Admins bypass managed-category composer lock; moderators do not.
    def bypasses_managed_category_lock?(user)
      return false if user.blank?
      user.admin?
    end
  end
end
