// Exhibition wall maths: turns a project's prints into framed boxes hung on
// a wall. Pure (no DOM, no Discourse imports) so the inline wall, the
// full-screen walk and a future generated wall image all share it.
//
// Everything is in abstract "wall units": every print's LONG EDGE is
// PRINT_LONG_EDGE units (the same print size for the whole show), so a pano
// reads wide, a vertical tall, and a square smaller than both. Callers scale
// the result to their container with percentages (x / width, y / height).

export const PRINT_LONG_EDGE = 100;

export const WALLS = Object.freeze({
  warm: { color: "#ece8e0", dark: false },
  gray: { color: "#cfccc6", dark: false },
  charcoal: { color: "#2f2e2c", dark: true },
});

export const MATS = Object.freeze({
  none: null,
  white: "#fbfaf7",
  offwhite: "#efeadf",
  black: "#1c1c1c",
});

export const FRAMES = Object.freeze({
  none: null,
  black: "#1f1f1f",
  wood: "#8b6b4a",
  white: "#f4f3ef",
});

export const LAYOUTS = Object.freeze(["line", "rows", "lead"]);

export const MAT_WIDTHS = Object.freeze({ narrow: 7, wide: 15 });

const FRAME_WIDTH = 3;
const GAP = 22; // between frames
const ROW_GAP = 30; // between rows (below the placard)
const PADDING = 36; // wall margin
const PLACARD = 16; // space reserved under each frame for its number
const LEAD_SCALE = 1.6;
const LINE_MAX = 5; // more prints than this hang in rows by default

// Presentation goal → starting look. A reader can change it ("Try a look");
// the photographer's own choice arrives with the project form.
const PRESETS = {
  gallery: { wall: "warm", mat: "white", matWidth: "wide", frame: "black" },
  web: { wall: "gray", mat: "none", matWidth: "narrow", frame: "none" },
  fun: { wall: "gray", mat: "none", matWidth: "narrow", frame: "none" },
  book: { wall: "warm", mat: "offwhite", matWidth: "narrow", frame: "none" },
  magazine: {
    wall: "warm",
    mat: "offwhite",
    matWidth: "narrow",
    frame: "none",
  },
  lwfull: { wall: "warm", mat: "offwhite", matWidth: "narrow", frame: "none" },
  lwis: { wall: "warm", mat: "offwhite", matWidth: "narrow", frame: "none" },
  on: { wall: "warm", mat: "offwhite", matWidth: "narrow", frame: "none" },
};
const DEFAULT_PRESET = {
  wall: "gray",
  mat: "white",
  matWidth: "wide",
  frame: "black",
};

export function defaultLayout(count) {
  return count > LINE_MAX ? "rows" : "line";
}

export function presetFor(intent, count) {
  return {
    ...(PRESETS[intent] ?? DEFAULT_PRESET),
    layout: defaultLayout(count),
  };
}

// Fills in anything missing or unknown in a saved/partial style.
export function normalizeStyle(style, intent, count) {
  const base = presetFor(intent, count);
  const pick = (value, allowed, fallback) =>
    allowed.includes(value) ? value : fallback;
  return {
    wall: pick(style?.wall, Object.keys(WALLS), base.wall),
    mat: pick(style?.mat, Object.keys(MATS), base.mat),
    matWidth: pick(style?.matWidth, Object.keys(MAT_WIDTHS), base.matWidth),
    frame: pick(style?.frame, Object.keys(FRAMES), base.frame),
    layout: pick(style?.layout, LAYOUTS, base.layout),
  };
}

export function aspectOf(image) {
  const w = Number(image?.original_width || image?.width) || 0;
  const h = Number(image?.original_height || image?.height) || 0;
  return w > 0 && h > 0 ? w / h : 1;
}

// One framed print, at `scale` × the standard print size. Returns sizes of
// the outer frame and the print inside it.
export function framedSize(aspect, style, scale = 1) {
  const long = PRINT_LONG_EDGE * scale;
  const printW = aspect >= 1 ? long : long * aspect;
  const printH = aspect >= 1 ? long / aspect : long;
  const mat = MATS[style.mat] ? MAT_WIDTHS[style.matWidth] * scale : 0;
  const frame = FRAMES[style.frame] ? FRAME_WIDTH * scale : 0;
  const border = mat + frame;
  return {
    w: printW + border * 2,
    h: printH + border * 2,
    printW,
    printH,
    mat,
    frame,
  };
}

function box(index, size, x, y) {
  const inset = size.mat + size.frame;
  return {
    index,
    x,
    y,
    w: size.w,
    h: size.h,
    frame: size.frame,
    mat: size.mat,
    print: { x: x + inset, y: y + inset, w: size.printW, h: size.printH },
    placardY: y + size.h,
  };
}

// Greedy rows no wider than `maxWidth`; each row hangs on its own centerline.
function hangRows(sizes, maxWidth, originX, originY) {
  const rows = [];
  let current = [];
  let used = 0;
  sizes.forEach((size, i) => {
    const needed = (current.length ? GAP : 0) + size.w;
    if (current.length && used + needed > maxWidth) {
      rows.push({ items: current, width: used });
      current = [];
      used = 0;
    }
    used += (current.length ? GAP : 0) + size.w;
    current.push({ size, i });
  });
  if (current.length) {
    rows.push({ items: current, width: used });
  }

  const widest = Math.max(...rows.map((row) => row.width));
  const boxes = [];
  let y = originY;
  rows.forEach((row, rowIndex) => {
    const rowH = Math.max(...row.items.map(({ size }) => size.h));
    let x = originX + (widest - row.width) / 2;
    row.items.forEach(({ size, i }) => {
      boxes.push(box(i, size, x, y + (rowH - size.h) / 2));
      x += size.w + GAP;
    });
    y += rowH + PLACARD + (rowIndex < rows.length - 1 ? ROW_GAP : 0);
  });
  return { boxes, width: widest, height: y - originY };
}

// Greedy row count for a given maximum row width.
function countRows(sizes, maxWidth) {
  let rows = 1;
  let used = 0;
  sizes.forEach((size, i) => {
    const needed = (i && used ? GAP : 0) + size.w;
    if (used && used + needed > maxWidth) {
      rows += 1;
      used = size.w;
    } else {
      used += needed;
    }
  });
  return rows;
}

// The narrowest row width that hangs `sizes` in at most `rowCount` rows, so
// rows come out roughly even instead of leaving one print alone at the end.
function rowWidthFor(sizes, rowCount) {
  const total =
    sizes.reduce((sum, size) => sum + size.w, 0) + GAP * (sizes.length - 1);
  const widest = Math.max(...sizes.map((size) => size.w));
  let width = Math.max(widest, total / rowCount);
  while (countRows(sizes, width) > rowCount && width < total) {
    width *= 1.02;
  }
  return width;
}

// Wide walls read better in a post than tall ones: up to 5 per row (fewer
// on a phone, via style.perRow).
function rowCountFor(count, perRow = 5) {
  return Math.max(1, Math.ceil(count / perRow));
}

// aspects: width/height of each print, in hanging order.
// Returns { width, height, boxes: [{ index, x, y, w, h, frame, mat, print,
// placardY }] } in wall units, including the wall margin.
export function layoutWall(aspects, style) {
  if (!aspects.length) {
    return { width: 0, height: 0, boxes: [] };
  }
  const layout = style.layout;

  if (layout === "lead" && aspects.length > 2) {
    const lead = framedSize(aspects[0], style, LEAD_SCALE);
    const rest = aspects.slice(1).map((aspect) => framedSize(aspect, style));
    const rowCount = rowCountFor(rest.length, style.perRow);
    const restX = PADDING + lead.w + GAP * 1.5;
    const grid = hangRows(rest, rowWidthFor(rest, rowCount), restX, 0);
    const height = Math.max(lead.h + PLACARD, grid.height);
    const leadBox = box(
      0,
      lead,
      PADDING,
      PADDING + (height - lead.h - PLACARD) / 2
    );
    const offsetY = PADDING + (height - grid.height) / 2;
    const restBoxes = grid.boxes.map((b) => ({
      ...b,
      index: b.index + 1,
      y: b.y + offsetY,
      placardY: b.placardY + offsetY,
      print: { ...b.print, y: b.print.y + offsetY },
    }));
    return {
      width: restX + grid.width + PADDING,
      height: height + PADDING * 2,
      boxes: [leadBox, ...restBoxes],
    };
  }

  const sizes = aspects.map((aspect) => framedSize(aspect, style));
  const rowCount =
    layout === "rows" ? rowCountFor(sizes.length, style.perRow) : 1;
  const maxWidth =
    rowCount === 1 ? Number.POSITIVE_INFINITY : rowWidthFor(sizes, rowCount);
  const hung = hangRows(sizes, maxWidth, PADDING, PADDING);
  return {
    width: hung.width + PADDING * 2,
    height: hung.height + PADDING * 2,
    boxes: hung.boxes,
  };
}

// Percent helpers for absolutely-positioned elements on a wall of
// `wall.width` × `wall.height` units.
export function percentRect(rect, wall) {
  return {
    left: (rect.x / wall.width) * 100,
    top: (rect.y / wall.height) * 100,
    width: (rect.w / wall.width) * 100,
    height: (rect.h / wall.height) * 100,
  };
}
