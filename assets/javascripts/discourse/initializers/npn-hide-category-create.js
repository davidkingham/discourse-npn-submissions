import { withPluginApi } from "discourse/lib/plugin-api";

// Hide the default category "Create Topic" button in managed critique categories
// for everyone except admins. The submission flows (Image Critique / Weekly
// Challenge / Project Critique) are the only sanctioned creation paths there,
// and the server-side guardian already blocks normal composer-create — so the
// button is a dead end for everyone else. The header "Create Post" dropdown
// (which is a theme component, not this button) stays the primary entry point.
//
// Approach: toggle a body class on route change; plugin CSS hides the button
// (the combo button that wraps it) when the class is set. Admins keep seeing
// it because they bypass the managed-category lock. Non-managed categories are
// unaffected. Replies and other actions are unaffected.

const BODY_CLASS = "npn-managed-category-create-hidden";

// The "category list" site setting serializes ids as "1|2|3".
function parseManagedIds(value) {
  return (value || "")
    .toString()
    .split("|")
    .map((s) => parseInt(s, 10))
    .filter((n) => Number.isInteger(n) && n > 0);
}

// Walk the active route + ancestors looking for a `category` attribute, so we
// also catch tag-within-category and subcategory list routes.
function categoryForRoute(route) {
  let r = route;
  while (r) {
    if (r.attributes?.category) {
      return r.attributes.category;
    }
    r = r.parent;
  }
  return null;
}

export default {
  name: "npn-hide-category-create",

  initialize(container) {
    const currentUser = container.lookup("service:current-user");
    const siteSettings = container.lookup("service:site-settings");
    const router = container.lookup("service:router");

    withPluginApi((api) => {
      api.onPageChange(() => {
        const body = document?.body;
        if (!body) {
          return;
        }

        const shouldHide = (() => {
          if (!siteSettings?.npn_submissions_enabled) {
            return false;
          }
          // Admins keep the button — they bypass the managed-category lock
          // server-side. Moderators do not bypass, so they're treated like
          // regular users here.
          if (currentUser?.admin) {
            return false;
          }
          const managedIds = parseManagedIds(
            siteSettings.npn_submissions_managed_category_ids
          );
          if (!managedIds.length) {
            return false;
          }
          const category = categoryForRoute(router?.currentRoute);
          return !!category && managedIds.includes(category.id);
        })();

        body.classList.toggle(BODY_CLASS, shouldHide);
      });
    });
  },
};
