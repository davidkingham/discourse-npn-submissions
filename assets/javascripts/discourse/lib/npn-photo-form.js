// Pure helpers for the photo-first image form (npn-photo-form.gjs). Kept here,
// free of components, so the rules that decide what reaches the server are
// unit-tested.

// The topics a photographer can tap to say what they're unsure about. `group`
// feeds focusFromTopics; `chip` names the existing form.chips.<focus>.<key>
// entry whose "think about" prompt and suggested wording the topic reuses.
export const TOPICS = [
  { key: "mood", group: "artistic", chip: "artistic.mood_feeling" },
  { key: "composition", group: "artistic", chip: "artistic.composition" },
  { key: "visual_flow", group: "artistic", chip: "artistic.visual_flow" },
  { key: "distractions", group: "artistic", chip: "artistic.distractions" },
  { key: "color", group: "either", chip: "technical.color" },
  { key: "processing", group: "either", chip: "technical.processing" },
  { key: "sharpness", group: "technical", chip: "technical.sharpness_focus" },
  { key: "exposure", group: "technical", chip: "technical.exposure" },
  { key: "unsure", group: "either", chip: "both.unresolved" },
];

const TOPIC_GROUPS = Object.fromEntries(TOPICS.map((t) => [t.key, t.group]));

// The server still stores a feedback focus (artistic / technical / both) and
// requires Technical Details when it is "technical". The photo-first form has
// no focus cards: the focus follows the tapped topics. Only purely technical
// topics make it "technical"; colour and processing sit in both camps, so they
// never tip it on their own.
export function focusFromTopics(topics) {
  const groups = new Set((topics || []).map((key) => TOPIC_GROUPS[key]));
  const artistic = groups.has("artistic");
  const technical = groups.has("technical");
  if (technical && !artistic && !groups.has("either")) {
    return "technical";
  }
  if (artistic && !technical && !groups.has("either")) {
    return "artistic";
  }
  return "both";
}

// "Camera: Canon EOS R5\nLens: RF 24-70\nAperture: f/11" → "Canon EOS R5 · RF
// 24-70 · f/11": the labeled block from npn-exif as one caption line. ISO keeps
// its label, since a bare number means nothing.
export function compactCameraLine(metadata) {
  return (metadata || "")
    .split("\n")
    .map((line) => {
      const at = line.indexOf(":");
      if (at < 0) {
        return line.trim();
      }
      const label = line.slice(0, at).trim();
      const value = line.slice(at + 1).trim();
      if (!value) {
        return "";
      }
      if (label === "ISO" || label === "Flash") {
        return `${label} ${value}`;
      }
      return value;
    })
    .filter(Boolean)
    .join(" · ");
}

// The camera data line and the typed notes are one Technical Details answer on
// the server. Camera data leads; a typed answer that already contains it (a
// resumed draft) is left alone so it isn't doubled.
export function mergeTechnicalDetails(cameraData, typed) {
  const camera = (cameraData || "").trim();
  const text = (typed || "").trim();
  if (!camera || text.includes(camera)) {
    return text;
  }
  return text ? `${camera}\n\n${text}` : camera;
}

// The photo-first form has one "story" box where the classic In-Depth style
// had three. A draft started there keeps everything: the two extra answers are
// folded into About This Image, in their original order.
export function foldInDepthFields(fields) {
  const next = { ...(fields || {}) };
  const story = ["about_this_image", "creative_intent", "creative_direction"]
    .map((key) => (next[key] || "").trim())
    .filter(Boolean)
    .join("\n\n");
  delete next.creative_intent;
  delete next.creative_direction;
  if (story) {
    next.about_this_image = story;
  }
  return next;
}
