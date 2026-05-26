import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

// Weekly Challenge context panel shown above the shared Image Critique form when
// type=weekly_challenge.
//
// When WordPress sync is configured and reachable, it shows the current
// challenge (title / dates / description / link) fetched from a cached
// server-side endpoint — the same source the preview and submitted post use, so
// they always agree. When sync is unavailable (unconfigured, offline, or the
// fetch fails) it falls back to the original static panel. The fetch never
// blocks the form: any error simply leaves the static fallback in place.
export default class NpnWeeklyChallengePanel extends Component {
  @service siteSettings;

  // Normalized { title, dates, description, url } from WordPress, or null.
  @tracked challenge = null;
  // False until the sync fetch has resolved (success or failure). We use this
  // to avoid flashing the static (blue-bar) fallback on first paint — the
  // static branch only renders once we KNOW the sync is unavailable.
  @tracked loaded = false;

  constructor() {
    super(...arguments);
    this.loadChallenge();
  }

  async loadChallenge() {
    try {
      const result = await ajax("/npn-submissions/weekly-challenge");
      this.challenge = result.challenge || null;
    } catch {
      // Graceful: keep the static fallback, never surface an error here.
      this.challenge = null;
    } finally {
      this.loaded = true;
    }
  }

  // Static fallback link (also the synced link's fallback if WordPress omits one).
  get fallbackUrl() {
    return this.siteSettings.npn_submissions_weekly_challenge_url;
  }

  get syncedLink() {
    return this.challenge?.url || this.fallbackUrl;
  }

  // Once the panel already shows the full challenge (title + dates + description)
  // the link is redundant, so we hide it. We only keep a link in the synced state
  // when the sync is partial (e.g. no description yet) and a URL is available.
  get showSyncedLink() {
    const c = this.challenge;
    if (!c) {
      return false;
    }
    const hasFullInfo = c.title && c.dates && c.description;
    return !hasFullInfo && !!this.syncedLink;
  }

  <template>
    <section
      class="npn-weekly-panel
        {{if this.challenge 'npn-weekly-panel--synced'}}
        {{unless this.loaded 'npn-weekly-panel--loading'}}"
      aria-busy={{if this.loaded "false" "true"}}
    >
      {{#if this.challenge}}
        <h3 class="npn-weekly-panel__title">
          {{i18n "npn_submissions.form.weekly.synced_title"}}
        </h3>
        <p class="npn-weekly-panel__challenge-title">
          {{this.challenge.title}}
        </p>
        {{#if this.challenge.dates}}
          <p class="npn-weekly-panel__dates">{{this.challenge.dates}}</p>
        {{/if}}
        {{#if this.challenge.description}}
          <p class="npn-weekly-panel__description">
            {{this.challenge.description}}
          </p>
        {{/if}}
        {{#if this.showSyncedLink}}
          <a
            class="npn-weekly-panel__link"
            href={{this.syncedLink}}
            target="_blank"
            rel="noopener noreferrer"
          >
            {{i18n "npn_submissions.form.weekly.synced_link"}}
          </a>
        {{/if}}
      {{else if this.loaded}}
        <h3 class="npn-weekly-panel__title">
          {{i18n "npn_submissions.form.weekly.title"}}
        </h3>
        <p class="npn-weekly-panel__text">
          {{i18n "npn_submissions.form.weekly.text"}}
        </p>
        {{#if this.fallbackUrl}}
          <a
            class="npn-weekly-panel__link"
            href={{this.fallbackUrl}}
            target="_blank"
            rel="noopener noreferrer"
          >
            {{i18n "npn_submissions.form.weekly.link"}}
          </a>
        {{/if}}
      {{else}}
        {{! Initial paint: synced-style chrome (no blue accent bar) with a quiet
        placeholder. When sync data arrives the heading stays put and only the
        body fills in, so the user never sees the static blue-bar variant flash
        before the real challenge appears. }}
        <h3 class="npn-weekly-panel__title">
          {{i18n "npn_submissions.form.weekly.synced_title"}}
        </h3>
        <p class="npn-weekly-panel__text">
          {{i18n "npn_submissions.form.weekly.loading"}}
        </p>
      {{/if}}
    </section>
  </template>
}
