# discourse-npn-submissions

A Discourse plugin that provides modern, guided submission flows for Nature
Photographers Network (NPN) critique content, replacing the previous Custom
Wizard setup. Every submission creates a **normal Discourse topic** in a
configured category, so nothing about reading, replying, moderation, search, or
backup changes.

## Purpose

Six submission flows, all served from a single focused workspace at `/submit`:

| Flow | URL | Posts to |
| --- | --- | --- |
| Image for Critique | `/submit?type=image` | critique category |
| Weekly Challenge | `/submit?type=weekly_challenge` | critique category (auto-tagged) |
| Project for Critique | `/submit?type=project` | project category (auto-tagged) |
| Introduction | `/submit?type=introduction` | introduction category |
| New Members Area image | `/submit?type=new_member_image` | new-member-image category |
| Help / Support | `/submit?type=help` | help category |

Weekly Challenge is the Image Critique flow in a context mode (different intro
copy, a weekly panel, and an auto-applied tag) — not a separate form. Project
Critique supports three methods: uploaded images, a PDF, or an external URL.

The last three are **lighter-weight** flows. **Introduction** and **Help** are
onboarding/support posts, not critiques — they're deliberately kept out of the
daily critique limit and the critique-style/feedback-focus machinery. The **New
Members Area image** is a gentle, low-pressure way for newer members to share a
single nature image and invite basic feedback ("About This Image" + "Feedback
Welcome", no critique style, no tags). It stays out of the daily limit too, but
it **is** annotatable in the critique workspace — see [Critique-workspace
integration](#critique-workspace-integration).

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
| `npn_submissions_introduction_category_id` | Category for Introduction topics. |
| `npn_submissions_new_member_image_category_id` | Category for New Members Area image topics. |
| `npn_submissions_help_category_id` | Category for Help / Support topics. |
| `npn_submissions_managed_category_ids` | Categories where non-admins may **not** create topics via the normal composer (each category served by a submission flow). |
| `npn_submissions_weekly_challenge_tag` | Tag auto-applied to Weekly Challenge submissions. Must already exist. |
| `npn_submissions_project_tag` | Tag auto-applied to Project submissions. Must already exist. |

If a target category setting is blank or points at a missing category, submission
fails with a clear 422 ("No target category is configured…") rather than posting
to the wrong place.

### Optional

| Setting | Default | Purpose |
| --- | --- | --- |
| `npn_submissions_descriptive_tag_group` | "" | Restrict the user's descriptive-tag picker to a tag group. |
| `npn_submissions_enforce_daily_limit` | `true` | One **critique** submission per user per local calendar day (the three critique types share the limit; Introduction / New Members Area image / Help are exempt; admins bypass; moderators do not). |
| `npn_submissions_max_single_images` | `5` (1–10) | Max images on an Image Critique. |
| `npn_submissions_min_project_images` | `6` (1–50) | Recommended minimum project images (warn-only). |
| `npn_submissions_max_project_images` | `12` (2–50) | Max main project images. |
| `npn_submissions_max_image_size_mb` | `8` (1–50) | Max upload size. |
| `npn_submissions_downsample_threshold_mb` | `3` (1–50) | Guidance-only threshold shown to users (not enforced server-side). |
| `npn_submissions_new_image_form_enabled` | `true` | Offer the photo-first image form (see [Photo-first image form](#photo-first-image-form)). Off withdraws the form and its links. |
| `npn_submissions_new_image_form_default` | `true` | Open the photo-first form by default; members can switch back and their choice is remembered in their browser. Off makes the classic form the default. |
| `npn_submissions_new_image_form_feedback_category_id` | "" | Category for the new form's "Tell us what you think" link, which opens a new topic titled "Feedback on the new submission form" there. Blank lets the member pick the category. |
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
- **Introduction** → `/submit?type=introduction`
- **New Members Area image** → `/submit?type=new_member_image`
- **Help / Support** → `/submit?type=help`
- **Start a Discussion** → keep the existing Discourse composer (a non-managed
  category)

For the New Members Area image and Introduction flows, the category-scoped CTA
buttons also render automatically on the corresponding category index pages
(gated on the matching `*_category_id` setting), so members don't have to find
the header link.

Remove any old Custom Wizard links. Because the managed categories are locked,
the normal composer will refuse new topics there for non-admins, so the only way
in is the submission flow.

## Critique-workspace integration

On success, every submission attaches a small, normalized bag of **topic custom
fields** (via `TopicMetadata`) that sibling plugins read — chiefly
[`discourse-npn-critique-reply`](https://github.com/davidkingham/discourse-npn-critique-reply),
which renders the visual critique workspace on submission topics. This plugin
owns the *original*-image references; the revised-image plugin owns revisions.

The contract is the shared `npn_*` field naming (there are no direct API calls
between the plugins):

- `npn_submission_type` + `npn_submission_schema_version` mark a topic as a
  submission — the presence signal the critique workspace keys off.
- `npn_original_primary_image_upload_id` / `npn_original_image_upload_ids` /
  `npn_original_primary_image_url` (+ `npn_critique_image_version_schema`,
  `npn_original_image_count`) put the submitted image(s) on the workspace's
  full-resolution annotation surface. Written for the **image-critique types**
  (`image`, `weekly_challenge`, `project`) **and New Members Area images** —
  `Submission::IMAGE_VERSION_TYPES`. Introduction/Help have no annotatable image
  and stay off this surface.
- The photographer's structured prose (`about_this_image`, `feedback_requested`,
  `technical_details`, …) is exposed live on the `topic_view` serializer (never
  shadowed into custom fields) so the workspace can pin the "Feedback Requested"
  ask. The New Members Area form stores its ask under the `feedback` key (its
  heading is "Feedback Welcome"); `npn_feedback_requested` falls back to it, so
  the pinned ask populates for new-member images too.

Net effect: **New Members Area images receive the same critique workspace as
regular critiques** — full-resolution canvas and pinned ask — while remaining
outside the daily limit and critique-style flow. The critique plugin still has
its own enable/category/group gates; if its `npn_critique_reply_enabled_category_ids`
is restricted rather than empty, add the New Members Area category to that list.

## Project sequences (Suggest a sequence)

Image-method project topics get tools for talking about image ORDER without
a list of bare numbers:

- **Project strip.** Replying on a project shows a numbered thumbnail strip
  (originals `Image 1…`, alternates `Alt A1…`) at the top of the composer.
  It can be collapsed, and the choice is remembered per browser.
- **Suggest a hang.** Available from the strip, from the composer
  toolbar's film icon, and in the critique workspace (where it takes the
  project wall's place in the left pane). It starts from the photographer's
  hang (`components/npn-hang-suggester.gjs`, built on the hang editor): the
  critic reorders (select a print and move it, or type `9, 8, 7, 5`), leaves
  prints out, brings in alternates, marks prints strongest ★ / keep ✓ /
  unsure ?, and — for a show or web gallery — changes layout, look and
  sizes. "Add to critique" draws it as one wall image with the marks and a
  "Left out" strip (`createSuggestionImage` in `lib/npn-hang-image.js`) and
  inserts it as a plain image whose alt text spells it out:

  ```
  ![Suggested hang (Option A): 9, 8, 7, 5, A1 · left out 3 · strongest 9 · lead print|690x420](upload://….jpeg)
  ```

  Adding one again under the same name replaces the image the critic added
  earlier in that session (matched by its upload, so a quoted or unrelated
  suggestion is never touched). "Add to critique" stays off until something
  differs from the photographer's version. The wording follows the
  goal: a book or magazine gets "Suggest a sequence" (no look controls), a
  LensWork / On Landscape submission "Suggest a selection" (no order).
  Helpers: `lib/npn-hang-suggestion.js`. Deliberately no wrapper markup, so
  the rich text editor handles it natively; selecting the image line in the
  Markdown editor and clicking the button again reopens it (older
  "Suggested sequence" images too).
- **True-proportion tiles.** The OP's Project Overview shows every image at the same height and its natural width, so panos,
  verticals and squares read at a glance. This is CSS only, so older project
  posts pick it up too.

- **Hang your show.** The project form has a hang editor
  (`components/npn-hang-editor.gjs`): one line / rows / lead print, wall,
  mat (and its width), frame, inches or cm. Each print is sized by dragging
  its corner grip or with – / +; sizes snap to standard long edges
  (`PRINT_SIZES`) and show live ("16 × 20 in"). Shift-click selects several;
  "Make all prints this size" matches them. A floor line and bench give
  scale, prints hang on a 57" centerline, and the readout shows the hang's
  width. Goals without physical prints (web, magazine/publication, book)
  hide sizing. Saved as `data.hang` (sizes keyed by upload id, see
  `lib/discourse_npn_submissions/project_hang.rb`). Like the images, the hang
  is locked once others reply (`Editor.media_signature`).
- **Book spreads.** For a Book goal the same section becomes "Plan Your
  Spreads": the images, in order, laid out spread by spread. Tap an image to
  put it on the left page, the right page or across both, pair it with the
  next image, or use it (or an alternate) as the cover; choose a portrait,
  square or landscape book. Saved on the hang as `book_format`, `cover`
  (upload id) and `spreads` (`[{ ids: [a, b] } | { ids: [a], side }]`);
  spreads follow the image order, so a saved pair is kept only while its
  two images are still consecutive (`resolveBook`, `layoutBook` in
  `lib/npn-wall-layout.js`). Critics of a book project get "Suggest
  spreads": the same pages in their tool, with the alt text spelling out the
  book (`… · facing 1+2 · across 3 · left page 5 · cover A1`).
- **Proposed orders.** For a show, a web gallery or a magazine project, the
  photographer can propose up to two alternative orders next to the main one
  ("Option A / B / C", renameable): the hang editor's Order tabs show the
  wall in each; an alternative is rearranged by typing `9, 8, 7 …` or with
  the move buttons. Saved on the hang as `order_name` and
  `orders: [{ name, ids }]`; an alternative only counts while it is a
  rearrangement of exactly the current images (`resolveOrders`). Each gets
  its own drawn picture (`hang_order_image_upload_ids`), placed after the
  main one in the post so email readers can compare; on the site the wall
  shows them as tabs. Print numbers are always the main order's.
- **Salon hang.** A physical show has a fourth layout, "Salon": every print
  placed by hand. It starts from where the prints hang in the current layout;
  drag a print to move it (a selected group moves together), and it snaps to
  the 57" centerline and to its neighbours' centres, edges and a 5" gap, with
  guide lines while dragging. Arrow keys nudge an inch (five with Shift).
  Saved on the hang as `positions` (`{ upload id: [x, y] }`: the print's
  centre in inches from the wall's left edge and above the floor;
  `layoutFree`, `snapPosition`). Proposed orders aren't offered for a salon
  hang, and on phones the post still shows rows of three.
- **The hang in the post.** On preview/submit/edit the browser draws the hang
  as one image (`lib/npn-hang-image.js`), uploads it, and the post builder
  puts it inside the project block as "The Exhibition"
  (`div.npn-project-hang`) instead of the Project Overview grid, so emails,
  previews and the topic thumbnail show the real hang. If drawing fails the
  grid is used.
- **Hangs in revisions.** A project revision (discourse-npn-revised-critique)
  carries its own hang and wall picture; `npn_project_images.hang` follows
  the latest revision's. That plugin uses `ProjectPostBuilder.hang_markup`,
  `ProjectHang.normalize`, and the builder service's `hangEditor` /
  `drawHangImage`.
- **Exhibition wall.** On the site, the photographer's hang is mounted over
  that image (or over the Overview grid on earlier posts, or at the top of
  older posts): framed, matted, numbered prints at their real sizes, the
  width readout, alternates on a panel at the same scale, tap to view large.
  On phones more than three prints hang in rows of three. Posts without a
  saved hang use the presentation goal's default look. Maths:
  `lib/npn-wall-layout.js` (inches); drawing: `components/npn-hang-wall.gjs`.
- **Walk the wall.** Full-screen walk along the wall
  (`components/npn-wall-walk.gjs`): current print centred, neighbours at the
  edges, arrow keys / swipe / thumbnail strip, Escape to close.
- **View the project.** The critique workspace's project wall steps through
  the images full-screen, in order, using Discourse's lightbox
  (`lib/npn-project-viewer.js`).
- **Requested feedback types.** The project form has an optional "What
  feedback would help most?" (overall cohesion, sequence, edit, individual
  images). Stored as `data.feedback_types`, written to the topic as
  `npn_project_feedback_types`, shown in the post under Feedback Requested,
  and included in `npn_project_images.feedback_types` so the workspace can
  put the matching tools first.

- **Older project topics (tag fallback).** Topics tagged
  `npn_submissions_project_fallback_tag` (default `project`) that have no
  submission record still get these tools, with images read from the first
  post (`lib/discourse_npn_submissions/project_post_images.rb`). It handles
  the live formats: the current Image Sequence, revised posts (ignores the
  "Original Submission" copy and revision blocks), the older masonry form
  (uses "Individual Images" once, matched by the sha1 in full URLs), and a
  leading cover image. Alternates come from an "Alternate Images" section.
  Fewer than two images means no tools. Set the setting blank to turn it off.

Data comes from the `npn_project_images` topic-view attribute
(`lib/discourse_npn_submissions/project_images.rb`). **Numbers match the
"Image N" labels the post shows now.** Without a revision that's the
submission order; after a project revision (discourse-npn-revised-critique,
`npn_project_revisions`), `originals` follow the latest revision's order and
replaced images, and `revision` holds its number. `slot_id` stays with an
image across revisions. The tag fallback also reads the presentation goal
from the post's "Presentation Goal" section.

The builder, the step-through viewer and the edit-sheet helpers are on the
`npn-sequence-builder` service. Code that is already
inside a modal (the critique workspace) renders `service.component` inline
instead of calling `open()`, because Discourse shows only one modal at a time.

## Photo-first image form

A second face for Image for Critique and the Weekly Challenge, offered beside
the classic form. It opens by default; the classic form is one link away.

- **Which form opens** (`lib/npn-form-choice.js`, used by `routes/submit.js`):
  the address wins (`/submit?type=image&form=new` or `&form=classic`, same for
  `type=weekly_challenge`), then the form the member last switched to
  (remembered in their browser's local storage), then the site default,
  `npn_submissions_new_image_form_default` (on = the new form).
- **Switching:** the new form has "Back to the classic form" and "Tell us what
  you think" at the top; the classic form shows "Switch to the new form".
  Switching either way saves what has been started, reopens it in the other
  form, and is remembered for next time.
- **What is different:** the photograph is shown large on a dark mat with the
  title as its caption; camera data read from the file is a line under it with
  an "Include in post" tick; tags are tappable when the descriptive tag group
  has 30 tags or fewer; there is one required question, with the feedback focus as three small pills
  above the box and ideas for what to ask tucked under it;
  the story and how-it-was-made boxes are one-line rows until opened; and
  "Ask for first impressions first" replaces the Initial Reaction card, with
  its own open-ended question prompts.
- **Weekly Challenge:** the same form at `type=weekly_challenge`, with this
  week's challenge panel at the top. The ideas list leads with questions about
  the theme, the story row becomes "Your take on the theme", and the summary
  shows the weekly tag the server adds.
- **What is the same:** everything the server sees. The form extends
  `NpnImageForm` and sends the same payload, so posts, drafts, preview, the
  daily limit and "edit with form" are unchanged (editing always opens the
  classic form). The critique style is Standard unless first impressions
  are switched on. The feedback focus is a row of three pills above the
  question (Artistic, Technical, Both) with Both already chosen; Technical
  requires technical details as before, which included camera data satisfies.
- **Going back:** turn `npn_submissions_new_image_form_default` off to make
  the classic form the default again (members who chose the new form keep
  it), or turn `npn_submissions_new_image_form_enabled` off to withdraw the
  new form altogether.

## Other submission pages

- **`/submit` chooser** (`npn-submit-chooser.gjs`): cards grouped by intent
  (share your work, say hello, get help), each with an icon and a line saying
  what it is for. The Weekly Challenge card shows this week's theme when
  WordPress sync has one.
- **New Members Area image** and **Introduction** use the photo-first look
  directly, with no opt-in: the photograph on a mat (`npn-photo-stage.gjs`),
  and the second, optional box as a one-line row until wanted. On the New
  Members form the title is the photograph's caption and the question box has
  tappable example questions. What they send to the server is unchanged.

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
