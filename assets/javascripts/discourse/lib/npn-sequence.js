// Shared helpers for project numbers: parsing and formatting the typed
// "1, 3, 4, A1" shorthand, labels, and the display size of a drawn image.
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

// Display size for the sheet in the post: Discourse's max content width,
// keeping the sheet's ratio. Clicking opens the full-size sheet.
export function sheetDisplaySize(width, height, maxWidth = 690) {
  if (!width || !height) {
    return { width: null, height: null };
  }
  const w = Math.min(width, maxWidth);
  return { width: w, height: Math.round((height * w) / width) };
}

export function numberLabel(number) {
  return number?.startsWith("A") ? `Alt ${number}` : `Image ${number}`;
}
