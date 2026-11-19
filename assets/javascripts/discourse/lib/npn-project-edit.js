import { formatShorthand } from "./npn-sequence";

// A critic's suggested EDIT of a project: each image tagged strongest / keep
// / unsure / cut, and alternates optionally "bring in". Rendered as one
// grouped contact sheet (npn-sequence-sheet.js createEditSheet) and inserted
// as a plain image whose alt text spells the edit out:
//
//   ![Suggested edit: strongest 4; keep 1, 3; unsure 7; cut 9; bring in A1|690x512](upload://….jpeg)
//
// Plain image on purpose (no wrapper markup) so the rich text editor handles
// it natively.

export const EDIT_TAGS = Object.freeze([
  Object.freeze({
    key: "strongest",
    symbol: "★",
    heading: "★ Strongest",
    altLabel: "strongest",
    color: "#a66a00",
    alternateOnly: false,
  }),
  Object.freeze({
    key: "keep",
    symbol: "✓",
    heading: "✓ Keep",
    altLabel: "keep",
    color: "#2e7d32",
    alternateOnly: false,
  }),
  Object.freeze({
    key: "unsure",
    symbol: "?",
    heading: "? Unsure",
    altLabel: "unsure",
    color: "#6b6b6b",
    alternateOnly: false,
  }),
  Object.freeze({
    key: "cut",
    symbol: "✕",
    heading: "✕ Cut",
    altLabel: "cut",
    color: "#c62828",
    alternateOnly: false,
  }),
  Object.freeze({
    key: "bring_in",
    symbol: "⤴",
    heading: "⤴ Bring in",
    altLabel: "bring in",
    color: "#2f6fb3",
    alternateOnly: true,
  }),
]);

export const EDIT_TAG_KEYS = Object.freeze(EDIT_TAGS.map((t) => t.key));

// Tags offered for one image: originals get strongest/keep/unsure/cut,
// alternates only "bring in".
export function tagsFor(number) {
  const isAlternate = String(number).startsWith("A");
  return EDIT_TAGS.filter((t) => t.alternateOnly === isAlternate);
}

// tags: { "4": "strongest", "A1": "bring_in", … }; images: the project's
// numbered images (originals then alternates). Returns the non-empty groups in
// display order, each with its images in project order.
export function editGroups(tags, images) {
  return EDIT_TAGS.map((tag) => ({
    tag,
    heading: tag.heading,
    color: tag.color,
    images: (images ?? []).filter(
      (image) => tags?.[image.number] === tag.key
    ),
  })).filter((group) => group.images.length);
}

export function hasEditTags(tags) {
  return Object.values(tags ?? {}).some((v) => EDIT_TAG_KEYS.includes(v));
}

export function editSummary(groups) {
  return groups
    .map(
      (group) =>
        `${group.tag.altLabel} ${formatShorthand(
          group.images.map((image) => image.number)
        )}`
    )
    .join("; ");
}

export function buildEditMarkup({ groups, image }) {
  const size =
    image?.width && image?.height ? `|${image.width}x${image.height}` : "";
  return `![Suggested edit: ${editSummary(groups)}${size}](${image.short_url})`;
}

const EDIT_IMAGE_REGEXP = /!\[Suggested edit:[^\]]*\]\([^)]*\)/;

export function containsEdit(text) {
  return EDIT_IMAGE_REGEXP.test(String(text ?? ""));
}

// Replaces the FIRST suggested-edit image in `text` with `markup`. Returns
// the new text, or null when there was none to replace.
export function replaceEditImage(text, markup) {
  const source = String(text ?? "");
  return EDIT_IMAGE_REGEXP.test(source)
    ? source.replace(EDIT_IMAGE_REGEXP, markup)
    : null;
}
