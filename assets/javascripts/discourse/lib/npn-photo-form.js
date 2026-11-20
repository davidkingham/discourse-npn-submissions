// Pure helpers for the photo-first image form (npn-photo-form.gjs). Kept here,
// free of components, so the rules that decide what reaches the server are
// unit-tested.

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
