// Shared helpers for suggested sequences: parsing the typed "1, 3, 4, A1"
// shorthand, building the image line the Suggest-a-Sequence builder inserts,
// and parsing it back for editing.
//
// Numbers are the image's ORIGINAL project number ("1"… for the submitted
// images, "A1"… for alternates). See
// lib/discourse_npn_submissions/project_images.rb for the numbering contract.
//
// A sequence is inserted as ONE plain markdown image (a contact sheet made by
// npn-sequence-sheet.js) — deliberately no custom wrapper markup, so the rich
// text editor handles it natively instead of bouncing the post to Markdown.

// Normalizes one shorthand token: "4" → "4", "a1" / "A 1" → "A1". Returns null
// for anything that isn't shaped like a project number.
export function normalizeNumber(token) {
  const cleaned = String(token ?? "")
    .replace(/\s+/g, "")
    .replace(/^#/, "")
    .toUpperCase();
  return /^(A?)([1-9]\d*)$/.test(cleaned) ? cleaned : null;
}

// "1, 3 4,A1" → { numbers: ["1","3","4","A1"], invalid: [], unknown: [] }.
// `known` (a Set of valid numbers) flags tokens that are well-formed but
// don't exist in this project. Duplicates are kept once, first wins.
export function parseShorthand(text, known) {
  const numbers = [];
  const invalid = [];
  const unknown = [];
  const tokens = String(text ?? "")
    .split(/[\s,;]+/)
    .filter(Boolean);

  for (const token of tokens) {
    const number = normalizeNumber(token);
    if (!number) {
      invalid.push(token);
    } else if (known && !known.has(number)) {
      unknown.push(number);
    } else if (!numbers.includes(number)) {
      numbers.push(number);
    }
  }
  return { numbers, invalid, unknown };
}

export function formatShorthand(numbers) {
  return (numbers ?? []).join(", ");
}

const ALT_PREFIX = "Suggested sequence";

// The label goes inside parentheses in alt text; drop characters that would
// break the markdown image or the parentheses.
function cleanLabel(label) {
  return String(label ?? "")
    .replace(/[()[\]|\n\r]/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

// The image line the builder inserts. The alt text carries the order (and the
// optional label) so screen readers and plain-text email get it, and so the
// builder can reopen it for editing:
//
//   ![Suggested sequence (Option A): 1, 3, 4, A1|690x368](upload://….jpeg)
export function buildSequenceMarkup({ label, numbers, image }) {
  const clean = cleanLabel(label);
  const alt = `${ALT_PREFIX}${clean ? ` (${clean})` : ""}: ${formatShorthand(
    numbers
  )}`;
  const size =
    image?.width && image?.height ? `|${image.width}x${image.height}` : "";
  return `![${alt}${size}](${image.short_url})`;
}

// Display size for the sheet in the post: Discourse's max content width,
// keeping the sheet's ratio. Clicking opens the full-size sheet.
export function sheetDisplaySize(width, height, maxWidth = 690) {
  if (!width || !height) {
    return { width: null, height: null };
  }
  const w = Math.min(width, maxWidth);
  return { width: w, height: Math.round((height * w) / width) };
}

const SEQUENCE_IMAGE_REGEXP =
  /!\[Suggested sequence(?: \(([^)]*)\))?: ([^\]|]*)(?:\|[^\]]*)?\]\([^)]*\)/i;

export function containsSequence(text) {
  return SEQUENCE_IMAGE_REGEXP.test(String(text ?? ""));
}

// Parses the FIRST suggested-sequence image in `text` back into
// { label, numbers }, or null if there isn't one. Used to reopen a sequence
// the critic already inserted (select it, click the button again).
export function parseSequenceMarkup(text) {
  const match = SEQUENCE_IMAGE_REGEXP.exec(String(text ?? ""));
  if (!match) {
    return null;
  }
  return {
    label: (match[1] ?? "").trim(),
    numbers: parseShorthand(match[2]).numbers,
  };
}

export function numberLabel(number) {
  return number?.startsWith("A") ? `Alt ${number}` : `Image ${number}`;
}
