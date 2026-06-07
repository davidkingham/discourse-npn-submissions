# frozen_string_literal: true

module DiscourseNpnSubmissions
  module DailyLimit
    class Exceeded < StandardError
    end

    module_function

    # Raises DiscourseNpnSubmissions::DailyLimit::Exceeded if `user` has already
    # submitted a critique today, evaluated in the user's local timezone.
    #
    # `tz_name` is the browser timezone string from
    # `Intl.DateTimeFormat().resolvedOptions().timeZone`. If it's missing or not
    # a zone we recognise we fall back to the server's configured timezone.
    def check!(user:, tz_name: nil)
      raise Exceeded if reached?(user: user, tz_name: tz_name)
      :ok
    end

    # Whether `user` is currently blocked by the daily limit (already submitted
    # a critique today in their local timezone). Lets the form surface the
    # limit up front while still allowing drafts. Returns false when the limit
    # is disabled or the user bypasses it.
    #
    # Only critique submission types count. Introductions are explicitly NOT
    # in the count — both because they don't belong to the critique-throttle
    # concept and so an introduction submitted today doesn't lock the user out
    # of a critique they're still entitled to make.
    def reached?(user:, tz_name: nil)
      return false if user.blank?
      return false unless SiteSetting.npn_submissions_enforce_daily_limit
      return false if Policy.bypasses_daily_limit?(user)

      zone = resolve_zone(tz_name)
      start_of_day = zone.now.beginning_of_day

      Submission
        .submitted
        .for_user(user)
        .where(submission_type: Submission::CRITIQUE_SUBMISSION_TYPES)
        .where("submitted_at >= ?", start_of_day)
        .exists?
    end

    def resolve_zone(tz_name)
      if tz_name.present?
        zone = ActiveSupport::TimeZone[tz_name.to_s]
        return zone if zone
      end
      Time.zone
    end
  end
end
