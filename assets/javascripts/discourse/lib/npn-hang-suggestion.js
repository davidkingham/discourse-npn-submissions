import { formatShorthand, parseShorthand } from "./npn-sequence";
import { presentationMode } from "./npn-wall-layout";

// A critic's suggested hang: their order (which prints hang, and where),
// what they left out, which alternates they brought in, a ranking mark on
// the prints they have an opinion on, and — for a show — their own layout,
// look and sizes. Rendered as ONE wall image (npn-hang-image.js) and
// inserted as a plain image whose alt text spells the suggestion out:
//
//   ![Suggested hang (Option A): 9, 8, 7, 5, A1 · left out 3 · strongest 9 · keep 1, 4 · lead print|690x420](upload://….jpeg)
//
// The wording follows how the project is presented (see presentationMode):
// a show or web gallery gets a "hang", a book or magazine a "sequence", and
// a LensWork / On Landscape submission a "selection" (no order: the
// publisher sequences it).
//
// Plain image on purpose (no wrapper markup) so the rich text editor handles
// it natively.

export const RANKS = Object.freeze([
  Object.freeze({
    key: "strongest",
    symbol: "★",
    altLabel: "strongest",
    color: "#a66a00",
  }),
  Object.freeze({
    key: "keep",
    symbol: "✓",
    altLabel: "keep",
    color: "#2e7d32",
  }),
  Object.freeze({
    key: "unsure",
    symbol: "?",
    altLabel: "unsure",
    color: "#6b6b6b",
  }),
]);
export const RANK_KEYS = Object.freeze(RANKS.map((r) => r.key));

const LAYOUT_WORDS = {
  line: "one line",
  rows: "rows",
  lead: "lead print",
};

const KINDS = {
  hang: "hang",
  page: "hang",
  sequence: "sequence",
  selection: "selection",
};

// "hang" | "sequence" | "selection" for a project's presentation goal.
export function suggestionKind(intent) {
  return KINDS[presentationMode(intent)] ?? "hang";
}

const SUGGESTION_REGEXP =
  /!\[Suggested (hang|sequence|selection)(?: \(([^)]*)\))?: ([^\]|]*)(?:\|[^\]]*)?\]\([^)]*\)/i;

function cleanLabel(label) {
  return String(label ?? "")
    .replace(/[()[\]|\n\r·]/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

function byProjectOrder(numbers) {
  return [...numbers].sort((a, b) => {
    const altA = a.startsWith("A");
    const altB = b.startsWith("A");
    if (altA !== altB) {
      return altA ? 1 : -1;
    }
    return parseInt(a.replace("A", ""), 10) - parseInt(b.replace("A", ""), 10);
  });
}

// The human-readable summary in the alt text (after the colon).
// suggestion: { order, ranks, layout?, originals: [numbers] , kind,
//               layoutChanged? }
export function suggestionSummary({
  kind,
  order,
  ranks,
  originals,
  layout,
  layoutChanged,
}) {
  const hung = new Set(order);
  const parts = [];
  if (kind !== "selection") {
    parts.push(formatShorthand(order));
  }
  const leftOut = originals.filter((n) => !hung.has(n));
  if (leftOut.length) {
    parts.push(`left out ${formatShorthand(leftOut)}`);
  }
  RANKS.forEach((rank) => {
    const numbers = byProjectOrder(
      order.filter((n) => ranks?.[n] === rank.key)
    );
    if (numbers.length) {
      parts.push(`${rank.altLabel} ${formatShorthand(numbers)}`);
    }
  });
  if (kind === "selection") {
    const brought = order.filter((n) => n.startsWith("A"));
    if (brought.length) {
      parts.push(`bring in ${formatShorthand(brought)}`);
    }
  }
  if (kind === "hang" && layoutChanged && LAYOUT_WORDS[layout]) {
    parts.push(LAYOUT_WORDS[layout]);
  }
  return parts.join(" · ");
}

export function buildSuggestionMarkup({ kind, label, summary, image }) {
  const clean = cleanLabel(label);
  const size =
    image?.width && image?.height ? `|${image.width}x${image.height}` : "";
  const title = `Suggested ${kind}${clean ? ` (${clean})` : ""}`;
  return `![${title}: ${summary}${size}](${image.short_url})`;
}

export function containsSuggestion(text) {
  return SUGGESTION_REGEXP.test(String(text ?? ""));
}

// Parses the FIRST suggestion image in `text` back into
// { kind, label, order, ranks, layout } so the tool can reopen it. Also
// reads the older "Suggested sequence (Label): 1, 3, A1" images.
// `known`: Set of the project's numbers; `originals`: original numbers in
// project order (a selection lists what's left out rather than the order).
export function parseSuggestion(text, { known, originals = [] } = {}) {
  const match = SUGGESTION_REGEXP.exec(String(text ?? ""));
  if (!match) {
    return null;
  }
  const kind = match[1].toLowerCase();
  const label = (match[2] ?? "").trim();
  const segments = match[3]
    .split("·")
    .map((s) => s.trim())
    .filter(Boolean);

  let order = null;
  const ranks = {};
  let leftOut = [];
  let brought = [];
  let layout = null;

  segments.forEach((segment) => {
    const lower = segment.toLowerCase();
    const listAfter = (prefix) =>
      parseShorthand(segment.slice(prefix.length), known).numbers;
    if (lower.startsWith("left out")) {
      leftOut = listAfter("left out");
    } else if (lower.startsWith("bring in")) {
      brought = listAfter("bring in");
    } else if (RANKS.some((r) => lower.startsWith(r.altLabel))) {
      const rank = RANKS.find((r) => lower.startsWith(r.altLabel));
      listAfter(rank.altLabel).forEach((n) => (ranks[n] = rank.key));
    } else if (Object.values(LAYOUT_WORDS).includes(lower)) {
      layout = Object.keys(LAYOUT_WORDS).find((k) => LAYOUT_WORDS[k] === lower);
    } else if (order === null) {
      order = parseShorthand(segment, known).numbers;
    }
  });

  if (order === null) {
    const out = new Set(leftOut);
    order = [...originals.filter((n) => !out.has(n)), ...brought];
  }
  return { kind, label, order, ranks, layout };
}

// The suggestion image in `text` that points at `shortUrl` (the upload a
// critic's earlier suggestion was drawn to), or null. Matching on the upload
// rather than the name means only the critic's OWN earlier image is ever
// replaced — never one inside a quote, or another unnamed suggestion.
export function findSuggestionByUpload(text, shortUrl) {
  if (!shortUrl) {
    return null;
  }
  const global = new RegExp(SUGGESTION_REGEXP.source, "gi");
  let match;
  while ((match = global.exec(String(text ?? "")))) {
    if (match[0].includes(`(${shortUrl}`)) {
      return match[0];
    }
  }
  return null;
}

// The upload:// URL of a suggestion image line, or null.
export function suggestionUpload(markup) {
  return /\]\((upload:\/\/[^)\s]+)/.exec(String(markup ?? ""))?.[1] ?? null;
}

export function normalizedLabel(label) {
  return cleanLabel(label).toLowerCase();
}
