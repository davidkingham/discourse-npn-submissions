# discourse-npn-submissions

A Discourse plugin that provides modern, guided submission flows for Nature
Photographers Network (NPN) critique content, replacing the previous Custom
Wizard setup. Every submission creates a **normal Discourse topic** in a
configured category, so nothing about reading, replying, moderation, search, or
backup changes.

## Purpose

Three submission flows, all served from a single focused workspace at `/submit`:

| Flow | URL | Posts to |
| --- | --- | --- |
| Image for Critique | `/submit?type=image` | critique category |
| Weekly Challenge | `/submit?type=weekly_challenge` | critique category (auto-tagged) |
| Project for Critique | `/submit?type=project` | project category (auto-tagged) |

Weekly Challenge is the Image Critique flow in a context mode (different intro
copy, a weekly panel, and an auto-applied tag) — not a separate form. Project
Critique supports three methods: uploaded images, a PDF, or an external URL.

Features: draft save/restore, debounced autosave, live preview modal,
drag-and-drop upload/reorder, per-image notes, Technical Details with a method
selector (enter text / upload a metadata screenshot / both) and quick templates,
a once-per-local-day submission limit, managed-category composer blocking, and an
admin troubleshooting dashboard.

## Installation

Standard Discourse plugin install:

```
cd /var/discourse
# add to containers/app.yml under hooks/after_code:
#   - git clone https://github.com/davidkingham/discourse-npn-submissions.git
./launcher rebuild app
```

### Dependencies

The profile **Setup** page (`/setup`) uses the geocoded location selector from
[`discourse-npn-locations`](https://github.com/davidkingham/discourse-npn-locations).
That plugin must be **installed and enabled** (`location_enabled` on) — the setup
form imports its `LocationSelector` component and stores the chosen place in the
`geo_location` user custom field that plugin owns. If `location_enabled` is off,
the location field is hidden; the rest of the setup page still works.

For local dev, clone into `plugins/` and restart `ember-cli` + `unicorn`/`puma`.

## Configuration

All settings live under **Admin → Settings → Plugins** (filter: `npn`). The
plugin does nothing until `npn_submissions_enabled` is on.

### Required before first use

| Setting | What to set |
| --- | --- |
| `npn_submissions_enabled` | Turn on. |
| `npn_submissions_allowed_groups` | Group(s) allowed to submit. **Defaults to `42`** — change this to your real members group id, or no one (except admins) can submit. |
| `npn_submissions_critique_category_id` | Category for Image Critique + Weekly Challenge topics. |
| `npn_submissions_project_category_id` | Category for Project Critique topics. |
| `npn_submissions_managed_category_ids` | Categories where non-admins may **not** create topics via the normal composer (the critique + project categories). |
| `npn_submissions_weekly_challenge_tag` | Tag auto-applied to Weekly Challenge submissions. Must already exist. |
| `npn_submissions_project_tag` | Tag auto-applied to Project submissions. Must already exist. |

If a target category setting is blank or points at a missing category, submission
fails with a clear 422 ("No target category is configured…") rather than posting
to the wrong place.

### Optional

| Setting | Default | Purpose |
| --- | --- | --- |
| `npn_submissions_descriptive_tag_group` | "" | Restrict the user's descriptive-tag picker to a tag group. |
| `npn_submissions_enforce_daily_limit` | `true` | One critique submission per user per local calendar day (all types share the limit; admins bypass; moderators do not). |
| `npn_submissions_max_single_images` | `5` (1–10) | Max images on an Image Critique. |
| `npn_submissions_min_project_images` | `6` (1–50) | Recommended minimum project images (warn-only). |
| `npn_submissions_max_project_images` | `12` (2–50) | Max main project images. |
| `npn_submissions_max_image_size_mb` | `8` (1–50) | Max upload size. |
| `npn_submissions_downsample_threshold_mb` | `3` (1–50) | Guidance-only threshold shown to users (not enforced server-side). |
| `npn_submissions_export_guide_url` | "" | "How to export" help link. |
| `npn_submissions_critique_guide_url` | "" | Critique guide help link. |
| `npn_submissions_project_guidelines_url` | "" | Project guidelines help link. |
| `npn_submissions_weekly_challenge_url` | "" | Human-facing Weekly Challenge page. Used as the panel link, and as the fallback panel when WordPress sync is unavailable. |
| `npn_submissions_weekly_challenge_api_url` | "" | WordPress REST endpoint for the current challenge (see [Weekly Challenge sync](#weekly-challenge-sync)). Leave blank to disable sync and use the static panel. |
| `npn_submissions_weekly_challenge_cache_minutes` | `30` (1–1440) | How long to cache the fetched challenge data. |
| `npn_submissions_site_support_url` | "" | Site support help link. |

> Note: the expected name `npn_submissions_allowed_group_id` from earlier specs
> is implemented as `npn_submissions_allowed_groups` (a group list supporting
> more than one group).

### Tags / categories to create first

- The weekly-challenge tag and project tag (auto-applied) must exist; the plugin
  never creates tags. Users must still pick at least one descriptive tag.
- Add the critique and project categories to `npn_submissions_managed_category_ids`
  so they can only be posted to through `/submit`.

### Weekly Challenge sync

When `npn_submissions_weekly_challenge_api_url` is set, the Weekly Challenge
panel, the post preview, and the submitted post all show the current challenge
pulled from WordPress (title + dates). When it's blank — or WordPress is
unreachable — everything falls back to the static panel and the human-facing
`npn_submissions_weekly_challenge_url` link, and submission is never blocked.

Recommended settings:

| Setting | Value |
| --- | --- |
| `npn_submissions_weekly_challenge_api_url` | `https://www.naturephotographers.network/wp-json/wp/v2/weekly-challenge?per_page=1&orderby=date&order=desc` |
| `npn_submissions_weekly_challenge_url` | The normal Weekly Challenge page on the site (human-facing). |

The endpoint is the `weekly-challenge` custom post type, sorted newest-first and
limited to one result, so it returns the latest **published** challenge. Weekly
Challenge posts are scheduled to publish each Sunday; scheduled-but-unpublished
posts do not appear in the REST feed, so the panel automatically rolls over to
the new challenge when WordPress publishes it.

How the response is read:

- The array is unwrapped and the **first** item is used.
- `acf.wc_title` → title, `acf.wc_dates` → dates, `acf.wc_description` → description.
- The post's `link` → the "View full challenge" URL.
- Flat `wc_*` fields and a pre-normalized `title`/`dates`/`description`/`url`
  shape are also accepted as fallbacks.
- An empty array, missing ACF fields, malformed JSON, or a failed request all
  degrade gracefully (last cached value, then the static panel).

Notes:

- The fetch is **server-side only**, SSRF-protected, with a short timeout, and
  cached for `npn_submissions_weekly_challenge_cache_minutes` (default 30). The
  browser never calls WordPress.
- Text from WordPress is decoded and stripped to plain text before display.
- `wc_description` is shown in the panel but is intentionally **not** inserted
  into the submitted post (the post identifies the challenge; it doesn't repeat
  the full prompt).
- Changing the API URL clears the cache automatically. Within a cache window the
  panel, preview, and submitted post always show the same challenge.

## Header link setup (theme component)

Point the "Create Post" dropdown (or header buttons) at the routes:

- **Image for Critique** → `/submit?type=image`
- **Weekly Challenge** → `/submit?type=weekly_challenge`
- **Project for Critique** → `/submit?type=project`
- **Start a Discussion** → keep the existing Discourse composer (a non-managed
  category)

Remove any old Custom Wizard links. Because the critique/project categories are
managed, the normal composer will refuse new topics there for non-admins, so the
only way in is the submission flow.

## Admin dashboard

**Admin → Plugins → NPN Submissions** (admin-only; moderators have no access).
Shows drafts, submitted items, and failed submissions with user, title, type,
project method, topic link, timestamps, upload summary, and error messages for
troubleshooting.

## Testing

Backend specs (run inside the Discourse repo with plugins loaded):

```
LOAD_PLUGINS=1 bin/rspec plugins/discourse-npn-submissions/spec
```

Covered: the Submitter service (all types, validation, daily limit, tags,
categories, upload roles, failure handling), the post builders, draft ownership,
and the request/admin controllers. See the QA checklist below for manual
browser testing.

## Rollback

The plugin only creates ordinary topics, so rollback is low-risk:

1. Revert the header theme-component links to the old Custom Wizard routes.
2. Turn off `npn_submissions_enabled`.
3. To restore normal composer in the critique/project categories, clear
   `npn_submissions_managed_category_ids`.
4. Confirm normal site behavior returns.
5. Leave created topics in place (they are normal topics).
6. Leave the plugin's tables in place unless a deliberate cleanup is planned;
   drafts created in the plugin remain stored but are inaccessible while disabled.

Re-enabling Custom Wizard (if still installed) plus the steps above fully
restores the previous flow.

## License

MIT.
