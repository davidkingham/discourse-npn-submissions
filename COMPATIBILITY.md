# Discourse Core Compatibility

A guide for staying on top of Discourse core changes, scoped to **what this
plugin actually does and uses**. Aimed at a future maintainer (or future-me)
deciding whether to upgrade Discourse core and what to test on staging first.

Everything below is sourced from the plugin's own code — file references are
given so each claim can be re-verified against the current tree.

---

## What this plugin does

The site uses three guided "submission flows" instead of the normal composer
for posting into the critique categories. The plugin owns those flows from
the form UI through to the created Topic.

| Submission type | Entry route | Backend model `submission_type` |
|---|---|---|
| Image Critique | `/submit?type=image` | `image` |
| Weekly Challenge | `/submit?type=weekly_challenge` | `weekly_challenge` |
| Project Critique | `/submit?type=project` | `project` |

Each flow:

1. Renders a dedicated form (Ember `gjs` class component under
   `assets/javascripts/discourse/components/npn-{image,project}-form.gjs`).
2. Autosaves the draft to its own `npn_submissions` row via
   `DraftStore` (`lib/discourse_npn_submissions/draft_store.rb`).
3. Validates client-side, mirrored server-side in `Submitter`
   (`lib/discourse_npn_submissions/submitter.rb`).
4. Composes the post body as Markdown via `PostBuilder` /
   `ProjectPostBuilder` (`lib/discourse_npn_submissions/*post_builder.rb`).
5. Creates the topic via `PostCreator.new(..., skip_guardian: true,
   skip_validations: true)` inside a transaction
   (`submitter.rb:370–378`).
6. Persists the user's uploads against the new submission and attaches
   a small bag of structured topic custom fields via `TopicMetadata`
   (`lib/discourse_npn_submissions/topic_metadata.rb`).
7. Optionally enriches Weekly Challenge submissions with WordPress-synced
   challenge identity (`lib/discourse_npn_submissions/weekly_challenge_info.rb`).

Supporting features in the same plugin:

- **Daily submission limit** — `lib/discourse_npn_submissions/daily_limit.rb`,
  toggleable via `npn_submissions_enforce_daily_limit`.
- **Managed-category lock** — a `Guardian` prepend that blocks normal topic
  creation in the configured critique categories
  (`lib/extensions/guardian_extension.rb` +
  `assets/javascripts/discourse/initializers/npn-hide-category-create.js`).
- **Admin dashboard** under `/admin/plugins/npn-submissions`
  (`assets/javascripts/discourse/admin-npn-submissions-route-map.js`,
  `app/controllers/discourse_npn_submissions/admin/submissions_controller.rb`).
- **In-field affordances**: `@mention` autocomplete (via the same APIs the
  composer uses) and an "Insert link" toolbar button.
- **Browser-side EXIF read** for an opt-in "Use photo metadata" helper
  (`assets/javascripts/discourse/lib/npn-exif.js`).
- **Original-image metadata** written to topic custom fields for the
  upcoming `discourse-revised-critique-image` /
  `discourse-npn-critique-reply` plugins (see `topic_metadata.rb`).

The plugin does **not** touch: reviewable/flag/notification surfaces, the
composer, badges, search, sidebar, or PMs.

---

## Discourse core surface area

Every external API the plugin reads from or writes to. Organised by
how visible the breakage would be if core changed the contract.

### Backend (Ruby) — high blast radius

These are load-bearing. A change in any of these is likely to need code
changes here.

| Surface | Used at | Notes |
|---|---|---|
| `PostCreator.new(..., skip_guardian: true, skip_validations: true)` | `submitter.rb:370` | Whole submission pipeline depends on this. If `PostCreator`'s constructor signature, options, or transactional contract changes, every submission path breaks. |
| `Guardian#can_create_topic_on_category?` (prepended) | `lib/extensions/guardian_extension.rb` | If this method moves, gets renamed, or its signature changes, the managed-category lock stops working and users can post via the normal composer into the critique categories. |
| `Topic.register_custom_field_type(key, :integer / :string / :json)` | `plugin.rb:55–67` | The `:json` type was a relatively recent addition; the legacy array-of-string shape is already deprecated. If `:json` ever loses support, `npn_original_image_upload_ids` typecasting breaks. |
| `Topic#upsert_custom_fields(hash)` | `topic_metadata.rb:237` | Deliberately used instead of `save_custom_fields` because the latter triggers full Topic validations (notably `DiscourseTagging`'s "you're allowed to tag" check, which fails for normal users on their own newly-created topic). If `upsert_custom_fields` is removed or changes semantics, all topic metadata silently disappears. |
| `UserUpload.exists?(upload_id:, user_id:)` | `submitter.rb:351` | The SHA1-dedup ownership check — the join row is treated as proof the user is allowed to attach the upload. If this table/join changes shape, valid re-uploads start rejecting. |
| `PrettyText.cook(markdown)` | `submissions_controller.rb:54` | Used for the preview modal so what the user sees matches the final post. If `cook` signature changes, Preview Post breaks. |
| `DiscourseTagging` validation (implicit, triggered inside `PostCreator`) | — | Submission applies tags via `PostCreator(... tags:)`; the inner validation runs during topic save. We've already had to work around its strictness once (see comment in `topic_metadata.rb:232–237`). |
| `Tag.where(name: ...).pluck(:name)` | `submitter.rb:318` | Existence check for user-chosen descriptive tags. Stable API. |
| `Discourse.warn_exception(e, message:)` | `submitter.rb:428`, `topic_metadata.rb:192,239` | Logster integration. We discovered the hard way that `Rails.logger.error("\n<backtrace>")` raises on production; this is the only safe path. If `warn_exception` changes signature, swallowed errors stop being logged but topic creation keeps working. |
| `FinalDestination::HTTP.start(...)` | `weekly_challenge_info.rb:98` | SSRF-protected HTTP client for the WordPress sync. The single network egress the plugin makes. |
| `Discourse.cache.{read,write,delete}` | `weekly_challenge_info.rb:41–62` | Standard Rails-cache-style API; stable. |
| `Discourse.store.cdn_url(url)` | `topic_metadata.rb:219` | URL resolution for the `npn_original_primary_image_url` custom field. Stable. |
| `AdminConstraint.new` in routes | `config/routes.rb:18` | Gates the admin namespace. Stable. |
| `add_admin_route`, `register_asset`, `register_svg_icon`, `enabled_site_setting`, `add_to_serializer`, `on(:site_setting_changed)`, `reloadable_patch` | `plugin.rb` | The plugin-DSL surface. Stable but verbose; renames here would require a wide find-replace. |
| `helper.allowList([...])` from `discourse-markdown` plugin loader | `assets/javascripts/lib/discourse-markdown/npn-submissions.js` | Lets the post body keep its `<div class="npn-*">` wrappers through cooking. If the allowlist API changes (or its plugin-loader filename convention), the project overview grid / Weekly Challenge callout / critique guidance card / metadata-screenshot wrapper all become plain `<div>`s that core's sanitizer strips. |

### Backend (Ruby) — lower risk but worth knowing

- `::ApplicationController`, `::Admin::AdminController` as controller base
  classes (`app/controllers/...`).
- `before_action :ensure_logged_in` from core.
- `Discourse::Application.routes.append { mount Engine, at: "/" }`
  (`plugin.rb`).
- `Rails::Engine` with `isolate_namespace` (`lib/discourse_npn_submissions/engine.rb`).
- `SiteSetting.npn_submissions_*` reads — see settings list under
  "Configuration" below.

### Frontend (JS / Ember) — high blast radius

The plugin uses several **newer** Discourse JS APIs that have moved during
recent core refactors. These are the most likely to bite on upgrade.

| Import | Used at | Notes |
|---|---|---|
| `TextareaTextManipulation`, `TextareaAutocompleteHandler` from `discourse/lib/textarea-text-manipulation` | `npn-field.gjs:9–10` | Powers `@mention` autocomplete and the Insert-link button. Moderately new API; has been reshuffled at least once across core versions. Wrapped in try/catch so a missing/renamed export degrades to "typing works, popup doesn't appear" rather than a broken field. |
| `dAutocomplete.setupAutocomplete` from `discourse/ui-kit/modifiers/d-autocomplete` | `npn-field.gjs:14,61` | New ui-kit modifier path. Required for `@mention` to work. Same try/catch fallback. |
| `userSearch` from `discourse/lib/user-search` | `npn-field.gjs:12` | Data source for `@mention`. Stable. |
| `UserAutocompleteResults` from `discourse/components/user-autocomplete-results` | `npn-field.gjs:8` | The popup itself. Component-class import — stable but moved between paths historically. |
| `DButton` from `discourse/ui-kit/d-button`, `DModal` from `discourse/ui-kit/d-modal`, `DCookText` from `discourse/ui-kit/d-cook-text`, `DNavItem` from `discourse/ui-kit/d-nav-item`, `dIcon` from `discourse/ui-kit/helpers/d-icon` | various form/modal/preview/admin components | The `discourse/ui-kit/*` namespace is the modern replacement for `discourse/components/*` for these primitives; the old paths still ship aliases in current Discourse, but the ui-kit paths are where active development happens. Likely to keep moving. |
| `TagChooser`, `MultiSelect`, `ComboBox` from `discourse/select-kit/components/*` | image form / project form | Select-kit is one of the more stable surfaces in core but its internals have churned (the option-mapping shape `{id, name}` is the contract we rely on). |
| `withPluginApi`, `api.setAdminPluginIcon`, `api.onPageChange` from `discourse/lib/plugin-api` | `initializers/npn-submissions-admin-plugin-configuration-nav.js`, `initializers/npn-hide-category-create.js` | Plugin-api version is not pinned. Both initializers handle missing APIs gracefully (the worst case is the admin icon is generic, or the legacy category Create button reappears for non-admins). |
| `lightbox` from `discourse/lib/lightbox` | preview / display flow | Image lightbox integration. |
| `ajax` from `discourse/lib/ajax`, `popupAjaxError` from `discourse/lib/ajax-error` | every controller-call site | Stable. |
| `i18n` from `discourse-i18n` | everywhere | Stable. |
| `eq` from `discourse/truth-helpers`, `bodyClass` from `discourse/helpers/body-class` | various | Stable. |
| `DiscourseRoute` from `discourse/routes/discourse` | `submit.js` route | Stable. |

### Conventions / scaffolding

- **Site settings** (`config/settings.yml`) under the `plugins:` root. Twenty
  declared settings, all `npn_submissions_*`-prefixed. Types used: default
  scalar, `group_list`, `list` (category list), `category`, `tag`,
  `tag_group_list`, `integer`. None of these are exotic — but if the
  `tag_group_list` or `group_list` type's storage format ever changes, the
  parsing in `lib/discourse_npn_submissions/policy.rb` (which splits on `|`)
  would need to follow.
- **Migrations** (`db/migrate/`): three of them, all standard
  `ActiveRecord::Migration[7.0]`. FK columns are `bigint` (matching core's
  `users.id` / `topics.id` / `uploads.id`).
- **Custom fields registered** (see `topic_metadata.rb` for the full key
  list):
  - integer: `npn_submission_schema_version`, `npn_wordpress_challenge_id`,
    `npn_critique_image_version_schema`,
    `npn_original_primary_image_upload_id`, `npn_original_image_count`
  - string: `npn_submission_type`, `npn_critique_style`,
    `npn_feedback_focus`, `npn_weekly_challenge_title`,
    `npn_weekly_challenge_dates`, `npn_wordpress_challenge_url`,
    `npn_original_primary_image_url`
  - json: `npn_original_image_upload_ids`

### Configuration the plugin depends on

These settings need to be populated for the plugin to do its job. The
plugin tolerates missing settings (degrades gracefully) but the user-facing
behaviour is incomplete:

| Setting | If unset… |
|---|---|
| `npn_submissions_enabled` | Plugin inert; routes 404. |
| `npn_submissions_allowed_groups` | No one can submit. |
| `npn_submissions_managed_category_ids` | Managed-category lock doesn't apply (composer Create button still visible). |
| `npn_submissions_critique_category_id` | Image / Weekly submissions fail with "No target category is configured". |
| `npn_submissions_project_category_id` | Project submissions fail the same way. |
| `npn_submissions_weekly_challenge_tag` | Weekly submissions skip the auto-tag. |
| `npn_submissions_descriptive_tag_group` | Tag chooser falls back to the unconstrained `TagChooser`. |
| `npn_submissions_weekly_challenge_api_url` | Weekly Challenge panel renders the calm "loading…" branch then shows no synced identity; submission still works without the WP context callout. |

---

## Most likely to break on core update

Sorted by probability × user impact. The first three are the watch list.

1. **`PostCreator.new(... skip_guardian: true, skip_validations: true)` + the surrounding transaction.**
   Single most load-bearing call in the plugin. If `PostCreator`'s
   constructor changes (e.g. options renamed, transaction semantics
   adjusted, `creator.errors` API changes), every submission flow
   breaks — Image / Weekly / Project all funnel through it
   (`submitter.rb:370–393`).

2. **`TextareaTextManipulation` + `dAutocomplete.setupAutocomplete` + `UserAutocompleteResults`.**
   The `@mention` autocomplete and Insert-link button live on this stack.
   `discourse/lib/textarea-text-manipulation` and the
   `discourse/ui-kit/modifiers/d-autocomplete` paths are newer APIs and
   have shifted in recent core releases. `npn-field.gjs:52–77` wraps the
   setup in try/catch, so a regression degrades — not crashes — to "typing
   works but no popup". Easy to miss on a smoke test if you don't actually
   try `@`.

3. **`discourse/ui-kit/*` imports** (`DButton`, `DModal`, `DCookText`, `DNavItem`, `dIcon`).
   The ui-kit namespace is where active development is happening — paths
   and component APIs have moved during this codebase's lifetime. A
   missing import would surface as a build error rather than runtime
   degradation (i.e. it'd be caught by CI). Watch for **prop-name** /
   **slot-name** changes, which silently render an empty modal or button.

4. **`DiscourseTagging` strictness during `PostCreator`.**
   Tag validation runs inside the topic save we delegate to `PostCreator`.
   We've already had to route around it once (the `upsert_custom_fields`
   choice in `topic_metadata.rb`). If core tightens it further (e.g. adds
   a per-category-required-tag check), submissions could start failing
   with a confusing error.

5. **The discourse-markdown allowlist plugin convention.**
   `assets/javascripts/lib/discourse-markdown/npn-submissions.js` defines
   `export function setup(helper) { helper.allowList([...]) }`. If the
   plugin-loader filename pattern changes, the helper API changes, or
   `allowList` is replaced (it was renamed from `whitelist` at one
   point), the post output loses its scoped wrappers and the Project
   Overview grid + Weekly Challenge callout + critique guidance card +
   metadata-screenshot wrapper all flatten to plain HTML.

6. **`Topic.register_custom_field_type(:json)` typecasting.**
   `npn_original_image_upload_ids` is the only `:json` field, but if the
   typecaster regresses to returning strings, the downstream critique
   reply plugin will see `"[123,456]"` instead of `[123, 456]`. The
   plugin's own code doesn't read this field back — but external
   consumers will.

7. **`FinalDestination::HTTP.start` API for the Weekly Challenge sync.**
   `weekly_challenge_info.rb:98` is the only external HTTP call in the
   plugin. The class has been reshuffled between `FinalDestination` and
   `FinalDestination::HTTP` historically. Failure mode is graceful: the
   sync returns nil, the panel shows its "loading…" branch indefinitely,
   submissions still work without the WP callout.

8. **Plugin-API methods** (`api.setAdminPluginIcon`, `api.onPageChange`).
   Both initializers are tolerant — `setAdminPluginIcon` just sets a nice
   icon, and `onPageChange` is a stable API. Worst case is the admin
   panel gets the default plugin icon, or the legacy category Create
   button starts appearing for non-admins (server-side guardian still
   blocks the actual create, so this is cosmetic).

9. **Select-kit option contract** (`{ id, name }` for `MultiSelect` /
    `TagChooser` / `ComboBox`).
    The contract is stable but select-kit internals churn. A regression
    here would surface as "the tag chooser doesn't accept selections" or
    "the project intent dropdown shows nothing".

10. **`Discourse.store.cdn_url` URL resolution.**
    Used once, for the `npn_original_primary_image_url` topic custom
    field. Stable API; worst case is a stale stored URL if site CDN
    config changes (the `upload_id` field is the durable source of
    truth, per the field's docstring).

---

## Manual regression checklist for staging

Run before promoting a Discourse core upgrade to production. Each section
maps to a concrete user-facing feature anchored in the code. The full
RSpec suite passing (`bin/rspec plugins/discourse-npn-submissions/spec`,
currently 177 examples) covers backend behaviour but doesn't catch JS /
template / select-kit / modal regressions — those are what this manual
pass is for.

### 0. Smoke — confirm the plugin still boots

- [ ] `/admin/plugins` shows **NPN Submissions** with the camera icon, not
      "default plugin icon" or missing entirely.
- [ ] `/admin/plugins/npn-submissions` loads without a 500 and shows the
      submitted/drafts/failed nav tabs.
- [ ] `/submit` loads and shows the type chooser.
- [ ] Discourse `/logs` is free of `[discourse-npn-submissions]` errors.

### 1. Image Critique flow

Path: `/submit?type=image` → fill form → Preview → Submit.

- [ ] **Daily-limit notice** at the top is visible **only if** the user
      has already submitted today (toggle by submitting once, reloading).
- [ ] **Image upload zone** — single drag-drop adds the main image with
      a thumbnail. Adding a second/third image enables per-image notes
      and the "Main" badge.
- [ ] **Photo metadata helper** — uploading a JPEG with EXIF surfaces
      the "Found photo metadata" panel. Clicking "Use photo metadata"
      appends to Technical Details (never overwrites existing text).
      Stripped/HEIC images show the calm "no metadata found" line.
- [ ] **Title** field required; submit blocked inline.
- [ ] **Tag chooser** — verify both branches: with
      `npn_submissions_descriptive_tag_group` set, a `MultiSelect`
      constrained to that group's tags shows; without it, the normal
      `TagChooser` shows. Both must accept selection.
- [ ] **Critique Style** + **Feedback Focus** — selecting either prompts
      for the other (after a submit attempt the prompts escalate).
- [ ] **Per-style question fields render correctly**:
  - Standard: About This Image + "What kind of feedback…"
  - In-Depth: About → Why This Image? → Express or Explore → Where Feedback
    Would Help Most. Only the last is `(required)`; the first three are
    `(optional)` and render in a visibly shorter textarea (compact field
    treatment).
  - Initial Reaction: Questions for Viewers (required) + hidden notes
    block (About, Technical Details, Feedback Requested After).
- [ ] **Markdown / @mention helper hint** appears at the top of the
      questions section (single hint, not repeated per field).
- [ ] **@mention autocomplete** — typing `@` in any question field opens
      the same user-autocomplete popup the composer uses. **This is the
      surface most likely to silently regress** — actually try it.
- [ ] **Insert link button** above each textarea — opens a modal with
      URL / text fields and a markdown-output note. Insert at caret puts
      `[text](url)` in the textarea, and the synthetic `input` event
      fires (autosave indicator goes to "Saving…").
- [ ] **Technical Details quick templates** — the "Field technique" /
      "Processing notes" / (when EXIF unavailable) "Basic camera EXIF"
      chips append to Technical Details after a blank line, never
      overwriting.
- [ ] **Feedback-lens chips** (under the required feedback field) —
      visible only once a Feedback Focus is selected. Clicking a chip
      opens a panel with **Think about** + **Suggested wording** + an
      explicit "Add suggested wording" button. Verify:
  - Clicking a chip does **not** write to the textarea.
  - "Add suggested wording" appends only the italicised suggested line.
  - Changing Feedback Focus collapses the open panel but **preserves**
    any typed text in the textarea.
- [ ] **Save Draft** + reload `/submit?type=image` → "Resume a saved draft"
      panel lists the draft; loading it restores every field including
      images and Technical Details.
- [ ] **Preview Post** modal — body matches what the final post will
      contain (the modal runs `PrettyText.cook` server-side). Tags
      appear under the title.
- [ ] **Submit** creates the topic in the critique category, redirects
      to the new topic page, post renders with the critique-guidance
      card + image(s) + headings in the expected order.
- [ ] Pop a Rails console:
      `Topic.last.custom_fields.slice("npn_submission_type", "npn_critique_style", "npn_feedback_focus", "npn_critique_image_version_schema", "npn_original_primary_image_upload_id", "npn_original_primary_image_url", "npn_original_image_upload_ids", "npn_original_image_count")`
      — every key should be present and well-typed (Array for upload_ids).

### 2. Weekly Challenge flow

Path: `/submit?type=weekly_challenge`.

- [ ] Weekly Challenge panel at the top fetches and displays the current
      challenge title + dates (from
      `npn_submissions_weekly_challenge_api_url`). If the WP endpoint is
      unreachable, the panel should render the calm "loading…"
      treatment without flashing the bright "synced" chrome.
- [ ] Submit auto-applies the `npn_submissions_weekly_challenge_tag`
      (visible on the created topic) **even if the user didn't select it**.
- [ ] Post body includes the Weekly Challenge context callout
      (`<div class="npn-weekly-challenge-context">…`) — confirms the
      markdown allowlist for that scoped class still survives cooking.
- [ ] `Topic.last.custom_fields.slice("npn_wordpress_challenge_id", "npn_weekly_challenge_title", "npn_weekly_challenge_dates", "npn_wordpress_challenge_url")`
      — populated when sync is available, absent when not.

### 3. Project Critique flow

Path: `/submit?type=project`.

- [ ] Method selector — Images / PDF / URL — switches the form between
      three layouts. For Images: at least
      `npn_submissions_min_project_images` (default 6) required, max
      `npn_submissions_max_project_images` (default 12); reorderable
      list; per-image optional note.
- [ ] PDF method — uploads a PDF and accepts an optional representative
      image. URL method — accepts URL + description + representative
      image.
- [ ] Submit creates a topic with the auto-applied
      `npn_submissions_project_tag`.
- [ ] **Project Overview grid** in the cooked post — the
      `<div class="npn-project-overview-grid">` / `…-frame` / `…-label`
      / `…-image` wrappers all survive cooking (otherwise the grid
      collapses to a vertical column of bare images). This is the most
      visible markdown-allowlist regression to look for.
- [ ] PDF / URL projects: post shows the
      `<div class="npn-project-access-card">` callout with download /
      visit button.

### 4. Drafts + autosave

- [ ] Starting a fresh submission and typing into any field starts the
      autosave indicator ("Saving…" → "Saved").
- [ ] Reloading the page shows the draft in "Resume a saved draft".
- [ ] Loading a draft, then "Start New" with unsaved changes prompts a
      confirm dialog; with no pending changes, resets silently.
- [ ] Discarding a draft from the resume list removes it.
- [ ] **Beta-draft compatibility** — an in-progress draft from before
      the In-Depth simplification (carrying `self_critique` data) opens
      without crashing; the `self_critique` text is silently dropped
      from the visible form and from the submitted post.

### 5. Managed-category lock

- [ ] As a non-admin, browse to the critique category index. The default
      "+ Create Topic" button should **not** appear (frontend hide via
      `npn-hide-category-create.js`).
- [ ] As a non-admin, attempt to create a topic in that category via the
      JSON API directly (`POST /posts.json` with `category=<id>`). The
      Guardian extension should reject it.
- [ ] As an admin, both UI and API path still work — admins bypass the
      lock.

### 6. Admin dashboard

`/admin/plugins/npn-submissions`.

- [ ] Submitted tab renders the table of submitted entries (paginated).
- [ ] Drafts tab renders the in-progress drafts table.
- [ ] Failed tab renders failed submissions with the stored
      `error_message`. (Use a deliberately-broken Submitter run to
      populate one if you don't have any — e.g. configure a category
      that doesn't exist.)
- [ ] Each row links to the corresponding topic / user / submission.

### 7. Daily limit

- [ ] As a normal user, submit one critique. Open `/submit` again — the
      red "daily limit reached" notice appears above the actions and the
      Submit button is disabled. Save Draft and Preview both stay
      enabled.
- [ ] As an admin (or with `npn_submissions_enforce_daily_limit` false),
      no limit is applied.

### 8. Server-side log check

After running the above:

- [ ] Discourse `/logs` is free of `[discourse-npn-submissions]`
      errors. A failed submission may surface a Logster entry from
      `Discourse.warn_exception` in `submitter.rb` — that's expected if
      you deliberately broke a submission to test the Failed tab; it
      should not appear during normal flows.

---

## When core changes anyway: where to look first

If something does break post-upgrade, the failure usually falls into one
of three buckets — and the right file to open is roughly the same in
each case.

| Symptom | First place to look |
|---|---|
| Submit returns a 500 / "Topic creation failed" | `lib/discourse_npn_submissions/submitter.rb` (the `PostCreator.new(...)` block) |
| `@mention` popup doesn't appear, or Insert link button no-ops | `assets/javascripts/discourse/components/npn-field.gjs` (the `setupTextarea` action's try/catch) |
| Post body in cooked topic loses its grid / cards / callouts | `assets/javascripts/lib/discourse-markdown/npn-submissions.js` (the `helper.allowList(...)` call) |
| Modal renders empty or doesn't open | the relevant `npn-*-modal.gjs` — usually a `DModal` / `DButton` prop renamed in ui-kit |
| Tag chooser broken | `MultiSelect` / `TagChooser` option shape in `npn-image-form.gjs` / `npn-project-form.gjs` |
| Topic created but no custom fields stored | `lib/discourse_npn_submissions/topic_metadata.rb` (`upsert_custom_fields` semantics) |
| Admin "+ Create Topic" reappears in managed categories | `lib/extensions/guardian_extension.rb` (the prepend on `can_create_topic_on_category?`) |

CI (`.github/workflows/discourse-plugin.yml`) runs the full RSpec suite
against Discourse `latest` weekly via cron — that's the early-warning
signal for backend breakage. JS / template / sanitizer regressions
generally won't show up there.

---

## Local CI parity: `bin/check`

The plugin ships a `bin/check` script that runs every gate the GitHub
Actions workflow runs, in CI order, with the same paths. Run it before
pushing a change you'd rather not see fail CI.

```
▶ Prettier            pnpm prettier --check .
▶ ESLint              pnpm eslint .
▶ Stylelint           pnpm stylelint "**/*.scss"
▶ Syntax Tree         bundle exec stree check (every .rb + Gemfile)
▶ RuboCop             bundle exec rubocop .
▶ i18n_lint           bundle exec ruby script/i18n_lint.rb …
▶ Migrations          RAILS_ENV=test bin/rake db:migrate
▶ RSpec               LOAD_PLUGINS=1 bin/rspec plugins/<plugin>/spec
```

The migrations gate exists because RSpec runs against an *already*-
migrated DB and skips `db:migrate`. The kind of mistake that gate
catches is a migration timestamp that Discourse's
`lib/tasks/db.rake` would reject — most commonly a future-dated
timestamp slipping past local checks. Without this gate, that fails
the next time someone (or production) actually runs `db:migrate`.

Invocation:

```bash
# inside the dev container
cd plugins/discourse-npn-submissions
bin/check

# from the macOS host (any working directory)
docker exec -u discourse <container> \
  /workspace/discourse/plugins/discourse-npn-submissions/bin/check
```

Properties worth knowing:

- **Doesn't bail early.** Every gate runs even if an earlier one fails,
  so one pass shows every issue. The exit code is the number of failed
  checks (`0` = clean).
- **Discovers its own paths.** Resolves the plugin root from the script
  location and the Discourse root from the plugin's position under
  `<discourse>/plugins/<name>/`. No CWD assumptions.
- **CI-faithful command shapes.** Uses the same `find … -print0 | xargs -0
  bundle exec stree check Gemfile` form CI does, the same `--ignore-
  workspace` resolution pnpm picks inside a plugin dir, and the same
  `LOAD_PLUGINS=1 bin/rspec` invocation core uses.

What it doesn't run (deliberate omissions):

- The `annotaterb` schema-annotation check from the workflow's
  `annotations_tests` job. Only relevant when migrations change and has
  historically produced false-positives against dev-container DB drift;
  trust CI for this one rather than the local pass.
- Anything against Discourse `stable` — the workflow's matrix was
  narrowed to `latest` only, since NPN's site runs `tests-passed`.

Total run time is ~25 seconds on this machine, dominated by RSpec
(~15s) and the JS gates (~5s combined).
