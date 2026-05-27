# frozen_string_literal: true

module DiscourseNpnSubmissions
  # Read-only, cached view of the "current Weekly Challenge" published in
  # WordPress. Used in three places, all server-side, so they can never disagree:
  # the Weekly Challenge panel endpoint, the preview, and the submitted post.
  #
  # The WordPress fetch is deliberately defensive: it runs only server-side, with
  # short timeouts and SSRF protection (FinalDestination::HTTP), tolerates several
  # JSON shapes, sanitizes every field to plain text, and NEVER raises. A failure
  # falls back to the last value we successfully fetched, and finally to nil — so
  # WordPress being slow or down can never block the form, preview, or submit.
  module WeeklyChallengeInfo
    # Cache keys are fixed (not derived from the URL) so changing the configured
    # endpoint and clearing the cache reliably drops the old site's data.
    PRIMARY_KEY = "npn_weekly_challenge/current"
    LAST_GOOD_KEY = "npn_weekly_challenge/last_good"

    # The last successful fetch is kept well beyond the normal cache window so it
    # can serve as a fallback through a WordPress outage.
    LAST_GOOD_TTL = 7.days

    # Short, bounded external HTTP timeouts (seconds).
    HTTP_TIMEOUT = 5

    # Plain-text length caps for the WordPress-provided fields.
    MAX_TITLE = 200
    MAX_DATES = 100
    MAX_DESCRIPTION = 1000

    module_function

    # Normalized current challenge: { title:, dates:, description:, url: } or nil.
    # `title` is always present when non-nil; `dates`/`description`/`url` may be
    # nil. Cached for npn_submissions_weekly_challenge_cache_minutes; throttled so
    # repeated calls during an outage don't re-hit WordPress every time.
    def current
      url = api_url
      return nil if url.blank?

      cached = Discourse.cache.read(PRIMARY_KEY)
      return cached[:value] if cached # wrapped so a cached nil is distinguishable

      result = fetch_and_normalize(url)

      if result
        Discourse.cache.write(PRIMARY_KEY, { value: result }, expires_in: cache_ttl)
        Discourse.cache.write(LAST_GOOD_KEY, result, expires_in: LAST_GOOD_TTL)
        result
      else
        # Serve (and throttle on) the last good value, or nil if we never had one.
        last_good = Discourse.cache.read(LAST_GOOD_KEY)
        Discourse.cache.write(PRIMARY_KEY, { value: last_good }, expires_in: cache_ttl)
        last_good
      end
    end

    # Drop cached data; the next #current re-fetches. Wired to a site-setting
    # change on the API URL, and available for manual refresh.
    def clear_cache
      Discourse.cache.delete(PRIMARY_KEY)
      Discourse.cache.delete(LAST_GOOD_KEY)
    end

    def api_url
      SiteSetting.npn_submissions_weekly_challenge_api_url.to_s.strip
    end

    def cache_ttl
      minutes = SiteSetting.npn_submissions_weekly_challenge_cache_minutes.to_i
      minutes = 30 if minutes <= 0
      minutes.minutes
    end

    # Fetch + normalize, returning the normalized hash or nil. Never raises:
    # any network/parse error is logged and treated as "unavailable".
    def fetch_and_normalize(url)
      body = fetch_remote(url)
      return nil if body.blank?

      normalize(JSON.parse(body))
    rescue JSON::ParserError => e
      log_failure("malformed JSON", e)
      nil
    rescue => e
      log_failure("unexpected error", e)
      nil
    end

    # Server-side only, SSRF-protected, short-timeout GET. Returns the response
    # body string on a 2xx, otherwise nil. Redirects are not followed; configure
    # the endpoint with its final scheme/host.
    def fetch_remote(url)
      uri = URI.parse(url)
      return nil unless uri.is_a?(URI::HTTP) && uri.host.present?

      body = nil
      FinalDestination::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.is_a?(URI::HTTPS),
        open_timeout: HTTP_TIMEOUT,
      ) do |http|
        http.read_timeout = HTTP_TIMEOUT
        request =
          Net::HTTP::Get.new(
            uri.request_uri,
            { "Accept" => "application/json", "User-Agent" => "Discourse NPN Submissions" },
          )
        response = http.request(request)
        body = response.body if response.is_a?(Net::HTTPSuccess)
      end
      body
    rescue URI::InvalidURIError => e
      log_failure("invalid URL", e)
      nil
    rescue => e
      # Timeouts, refused connections, SSRF-blocked IPs, TLS errors, etc.
      log_failure("fetch failed", e)
      nil
    end

    # Map a parsed WordPress response to our normalized shape. Tolerates, in
    # priority order: ACF-in-REST (acf.wc_*), flat custom (wc_*), and an already
    # normalized payload (title/dates/description). Collection endpoints return an
    # array — use the first entry. Returns nil unless a usable title is present.
    def normalize(parsed)
      node = parsed.is_a?(Array) ? parsed.first : parsed
      return nil unless node.is_a?(Hash)

      node = node.with_indifferent_access
      acf = node[:acf].is_a?(Hash) ? node[:acf].with_indifferent_access : {}

      title = clean(acf[:wc_title] || node[:wc_title] || node[:title], MAX_TITLE)
      return nil if title.blank?

      {
        # The WordPress post id — durable grouping key for future Weekly
        # Challenge archive/filter features (one challenge can be the target of
        # many submissions; the post id is the only stable identifier).
        id: clean_int(node[:id] || acf[:wc_id]),
        title: title,
        dates: clean(acf[:wc_dates] || node[:wc_dates] || node[:dates], MAX_DATES),
        description:
          clean(acf[:wc_description] || node[:wc_description] || node[:description], MAX_DESCRIPTION),
        url: clean_url(node[:link] || node[:url]),
      }
    end

    def clean_int(value)
      return nil if value.nil?
      n = value.to_i
      n.positive? ? n : nil
    rescue StandardError
      nil
    end

    # Reduce a WordPress value to safe, length-capped plain text. Nokogiri's
    # fragment #text strips all tags and decodes every HTML entity (including
    # named ones like &nbsp; and &#8211;) in one pass.
    def clean(value, max)
      return nil if value.nil?

      text = Nokogiri::HTML5.fragment(value.to_s).text
      # Collapse whitespace runs to single spaces.   (non-breaking space,
      # from &nbsp;) is matched explicitly because Ruby's \s does not include it.
      text = text.gsub(/[\s\u00A0]+/, " ").strip
      return nil if text.blank?

      text.length > max ? "#{text[0, max].rstrip}…" : text
    end

    def clean_url(value)
      url = value.to_s.strip
      return nil if url.blank?

      uri = URI.parse(url)
      uri.is_a?(URI::HTTP) && uri.host.present? ? url : nil
    rescue URI::InvalidURIError
      nil
    end

    def log_failure(reason, error)
      Rails.logger.warn(
        "[discourse-npn-submissions] Weekly Challenge fetch #{reason}: #{error.class}: #{error.message}",
      )
    end
  end
end
