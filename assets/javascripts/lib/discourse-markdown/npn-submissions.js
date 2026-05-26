// Allow the plugin's scoped post markup to survive cooking, so plugin CSS can
// lay it out. Without this, Discourse's sanitizer strips the unknown classes.
// Covers the Project Access card (PDF/URL projects), the metadata-screenshot
// wrapper (Technical Details), the Weekly Challenge context callout, and the
// critique guidance card.
export function setup(helper) {
  helper.allowList([
    "div.npn-project-access-card",
    "a.npn-project-access-thumb",
    "div.npn-project-access-content",
    "span.npn-project-access-label",
    "div.npn-project-access-title",
    "div.npn-project-access-desc",
    "a.npn-project-access-button",
    "div.npn-metadata-screenshot",
    "div.npn-weekly-challenge-context",
    "div.npn-weekly-challenge-title",
    "div.npn-weekly-challenge-dates",
    "div.npn-critique-guidance",
    "div.npn-critique-guidance-row",
    "div.npn-project-overview-grid",
    "div.npn-project-overview-item",
    "div.npn-project-overview-label",
    "div.npn-project-overview-frame",
    "img.npn-project-overview-image",
    "img[loading]",
  ]);
}
