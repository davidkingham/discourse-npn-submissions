// Exhibition wall maths, in real INCHES: turns a project's prints into framed
// boxes hung on a wall. Pure (no DOM, no Discourse imports) so the hang
// editor, the exhibition wall, the full-screen walk and the drawn wall image
// all share it.
//
// A print's size is its LONG edge in inches (snapped to standard sizes); the
// short edge follows the image's proportions. Physical walls hang on a 57"
// centerline above a floor line, with a bench for scale. Callers scale the
// result to their container with percentages (x / width, y / height).

export const PRINT_SIZES = Object.freeze([
  8, 10, 12, 14, 16, 20, 24, 30, 36, 40, 48, 60,
]);
export const DEFAULT_PRINT_SIZE = 20;
export const MAT_WIDTHS = Object.freeze([2, 3, 4]);
export const LAYOUTS = Object.freeze(["line", "rows", "lead"]);

export const WALLS = Object.freeze({
  warm: { color: "#ece8e0", floor: "#d9d3c7", dark: false },
  gray: { color: "#cfccc6", floor: "#b9b5ad", dark: false },
  charcoal: { color: "#2f2e2c", floor: "#232220", dark: true },
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

const FRAME_WIDTH = 1;
const GAP = { line: 10, rows: 5, lead: 5 };
const ROW_GAP = 6;
const PLACARD = 3; // space under each frame for its number
const CENTERLINE = 57; // gallery standard: centre of the hang above the floor
const MARGIN_X = 30;
const MARGIN_TOP = 14;
const FLOOR = 10; // floor strip drawn below the floor line
const BENCH = { w: 48, h: 18 };
const BENCH_CLEARANCE = 8;
const DIGITAL_MARGIN = 10;
const LINE_MAX = 5; // more prints than this hang in rows by default

// How a project is presented depends on where it's headed:
// - "hang"      a physical show (gallery, just for fun, other, not chosen):
//               the photographer hangs it at real sizes, with mats/frames.
// - "page"      a web gallery: layout and page colour, no sizes or frames.
// - "spreads"   a book: the photographer plans the spreads — which images
//               face each other, which run across both pages, the cover.
// - "sequence"  a magazine: the order matters, the publisher lays it out —
//               a plain numbered preview.
// - "selection" LensWork / On Landscape: the publisher decides sequence and
//               layout, so the question is which images are strongest.
const MODES = {
  web: "page",
  book: "spreads",
  magazine: "sequence",
  lwfull: "selection",
  lwis: "selection",
  on: "selection",
};

export function presentationMode(intent) {
  return MODES[intent] ?? "hang";
}

// A book's page shape (width / height of ONE page).
export const BOOK_FORMATS = Object.freeze({
  portrait: 0.8,
  square: 1,
  landscape: 1.25,
});
// Where a spread's single image sits.
export const SPREAD_SIDES = Object.freeze(["right", "left", "full"]);

// Presentation goal → starting look.
const PRESETS = {
  gallery: { wall: "warm", mat: "white", matWidth: 3, frame: "black" },
  fun: { wall: "gray", mat: "white", matWidth: 2, frame: "black" },
  web: { wall: "gray", mat: "none", matWidth: 2, frame: "none" },
  book: { wall: "warm", mat: "none", matWidth: 2, frame: "none" },
  magazine: { wall: "warm", mat: "none", matWidth: 2, frame: "none" },
  lwfull: { wall: "gray", mat: "none", matWidth: 2, frame: "none" },
  lwis: { wall: "gray", mat: "none", matWidth: 2, frame: "none" },
  on: { wall: "gray", mat: "none", matWidth: 2, frame: "none" },
};
const DEFAULT_PRESET = {
  wall: "gray",
  mat: "white",
  matWidth: 3,
  frame: "black",
};

// Only a physical show has print sizes, a floor and a bench.
export function physicalGoal(intent) {
  return presentationMode(intent) === "hang";
}

export function defaultLayout(count) {
  return count > LINE_MAX ? "rows" : "line";
}

// The full hang for a set of images: the saved hang (server shape, snake_case
// keys) with gaps filled from the goal's preset. `images` are the prints in
// hanging order ({ upload_id, … }).
// `pool`: every image a book cover may be chosen from (the prints plus any
// alternates); defaults to the prints.
export function resolveHang(hang, intent, images, pool = images) {
  const base = PRESETS[intent] ?? DEFAULT_PRESET;
  const pick = (value, allowed, fallback) =>
    allowed.includes(value) ? value : fallback;
  const physical = physicalGoal(intent);
  const sizes = images.map((image) => {
    const size = Number(hang?.sizes?.[String(image.upload_id)]);
    return physical && PRINT_SIZES.includes(size) ? size : DEFAULT_PRINT_SIZE;
  });
  const mode = presentationMode(intent);
  // Only a hang has mats and frames; only a hang or a web page has a
  // chosen layout and wall. Values saved under another goal are kept on
  // the hang (in case the goal changes back) but not shown.
  const styled = mode === "hang";
  const laidOut = mode === "hang" || mode === "page";
  return {
    mode,
    layout: laidOut
      ? pick(hang?.layout, LAYOUTS, defaultLayout(images.length))
      : "rows",
    wall: laidOut ? pick(hang?.wall, Object.keys(WALLS), base.wall) : base.wall,
    mat: styled ? pick(hang?.mat, Object.keys(MATS), base.mat) : "none",
    matWidth: pick(Number(hang?.mat_width), MAT_WIDTHS, base.matWidth),
    frame: styled ? pick(hang?.frame, Object.keys(FRAMES), base.frame) : "none",
    unit: hang?.unit === "cm" ? "cm" : "in",
    physical,
    sizes,
    ...(mode === "spreads" ? resolveBook(hang, images, pool, base) : {}),
  };
}

// The book for these images, in their order: each spread holds one image
// (on the right page, the left page, or across both) or two consecutive
// images facing each other. Saved spreads are honoured where they still
// match the order; everything else is one image per spread, on the right.
function resolveBook(hang, images, pool, base) {
  const saved = new Map();
  (Array.isArray(hang?.spreads) ? hang.spreads : []).forEach((spread) => {
    const ids = (spread?.ids ?? []).map(String);
    if (ids.length) {
      saved.set(ids[0], { ids, side: spread.side });
    }
  });

  const spreads = [];
  for (let i = 0; i < images.length; i++) {
    const id = String(images[i].upload_id);
    const next = images[i + 1] ? String(images[i + 1].upload_id) : null;
    const was = saved.get(id);
    if (was?.ids.length === 2 && was.ids[1] === next) {
      spreads.push({ indexes: [i, i + 1], side: null });
      i++;
    } else {
      spreads.push({
        indexes: [i],
        side: SPREAD_SIDES.includes(was?.side) ? was.side : "right",
      });
    }
  }

  const coverId = hang?.cover ? String(hang.cover) : null;
  const coverImage = coverId
    ? ((pool ?? images).find((image) => String(image.upload_id) === coverId) ??
      null)
    : null;

  return {
    wall: Object.keys(WALLS).includes(hang?.wall) ? hang.wall : base.wall,
    bookFormat: Object.keys(BOOK_FORMATS).includes(hang?.book_format)
      ? hang.book_format
      : "portrait",
    spreads,
    coverImage,
  };
}

// A resolved hang back in the saved (server) shape, merged over the
// `previous` saved hang so settings that don't apply to the current goal
// (mats and sizes while the goal is a web gallery, say) survive a goal
// change and come back if the photographer switches back.
export function serializeHang(style, images, previous = null) {
  const out = {
    ...(previous ?? {}),
    layout: style.layout,
    wall: style.wall,
    unit: style.unit,
  };
  if (style.mode === "spreads") {
    Object.assign(out, {
      book_format: style.bookFormat,
      cover: style.coverImage ? style.coverImage.upload_id : null,
      spreads: style.spreads.map((spread) => ({
        ids: spread.indexes.map((i) => images[i].upload_id),
        ...(spread.indexes.length === 1 ? { side: spread.side } : {}),
      })),
    });
  }
  if (style.mode === "hang") {
    // Keep the sizes of prints that aren't hung right now (a critic's
    // left-out print keeps its size if it's put back).
    const sizes = { ...(previous?.sizes ?? {}) };
    images.forEach((image, index) => {
      sizes[String(image.upload_id)] = style.sizes[index];
    });
    Object.assign(out, {
      mat: style.mat,
      mat_width: style.matWidth,
      frame: style.frame,
      sizes,
    });
  }
  return out;
}

export function aspectOf(image) {
  const w = Number(image?.original_width || image?.width) || 0;
  const h = Number(image?.original_height || image?.height) || 0;
  return w > 0 && h > 0 ? w / h : 1;
}

// --- sizes -------------------------------------------------------------------

export function snapSize(longEdge) {
  return PRINT_SIZES.reduce((best, size) =>
    Math.abs(size - longEdge) < Math.abs(best - longEdge) ? size : best
  );
}

export function stepSize(longEdge, direction) {
  const index = PRINT_SIZES.indexOf(snapSize(longEdge));
  const next = Math.max(0, Math.min(PRINT_SIZES.length - 1, index + direction));
  return PRINT_SIZES[next];
}

function roundHalf(value) {
  return Math.round(value * 2) / 2;
}

// "16 × 20 in" (width × height) or "41 × 51 cm".
export function formatPrintSize(longEdge, aspect, unit = "in") {
  const w = aspect >= 1 ? longEdge : longEdge * aspect;
  const h = aspect >= 1 ? longEdge / aspect : longEdge;
  if (unit === "cm") {
    return `${Math.round(w * 2.54)} × ${Math.round(h * 2.54)} cm`;
  }
  return `${roundHalf(w)} × ${roundHalf(h)} in`;
}

// "14 ft 2 in" or "4.3 m".
export function formatWallWidth(inches, unit = "in") {
  if (unit === "cm") {
    return `${(Math.round((inches * 2.54) / 10) / 10).toFixed(1)} m`;
  }
  const total = Math.round(inches);
  const feet = Math.floor(total / 12);
  const rest = total % 12;
  return rest ? `${feet} ft ${rest} in` : `${feet} ft`;
}

// --- layout ------------------------------------------------------------------

// One framed print. Returns the outer frame size and the print inside it.
export function framedSize(aspect, longEdge, style) {
  const printW = aspect >= 1 ? longEdge : longEdge * aspect;
  const printH = aspect >= 1 ? longEdge / aspect : longEdge;
  const mat = MATS[style.mat] ? style.matWidth : 0;
  const frame = FRAMES[style.frame] ? FRAME_WIDTH : 0;
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

function countRows(sizes, maxWidth, gap) {
  let rows = 1;
  let used = 0;
  sizes.forEach((size) => {
    const needed = (used ? gap : 0) + size.w;
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
function rowWidthFor(sizes, rowCount, gap) {
  const total =
    sizes.reduce((sum, size) => sum + size.w, 0) + gap * (sizes.length - 1);
  const widest = Math.max(...sizes.map((size) => size.w));
  let width = Math.max(widest, total / rowCount);
  while (countRows(sizes, width, gap) > rowCount && width < total) {
    width *= 1.02;
  }
  return width;
}

function rowCountFor(count, perRow = 5) {
  return Math.max(1, Math.ceil(count / perRow));
}

// Rows no wider than `maxWidth`; each row hangs on its own centerline.
// Positions are relative to (0, 0) = top-left of the group.
function hangRows(sizes, maxWidth, gap) {
  const rows = [];
  let current = [];
  let used = 0;
  sizes.forEach((size, i) => {
    const needed = (current.length ? gap : 0) + size.w;
    if (current.length && used + needed > maxWidth) {
      rows.push({ items: current, width: used });
      current = [];
      used = 0;
    }
    used += (current.length ? gap : 0) + size.w;
    current.push({ size, i });
  });
  if (current.length) {
    rows.push({ items: current, width: used });
  }

  const widest = Math.max(...rows.map((row) => row.width));
  const boxes = [];
  let y = 0;
  rows.forEach((row, rowIndex) => {
    const rowH = Math.max(...row.items.map(({ size }) => size.h));
    let x = (widest - row.width) / 2;
    row.items.forEach(({ size, i }) => {
      boxes.push(box(i, size, x, y + (rowH - size.h) / 2));
      x += size.w + gap;
    });
    y += rowH + PLACARD + (rowIndex < rows.length - 1 ? ROW_GAP : 0);
  });
  return { boxes, width: widest, height: y };
}

function shift(b, dx, dy) {
  return {
    ...b,
    x: b.x + dx,
    y: b.y + dy,
    placardY: b.placardY + dy,
    print: { ...b.print, x: b.print.x + dx, y: b.print.y + dy },
  };
}

// The group of framed prints (no wall yet), relative to its own top-left.
function arrange(aspects, style) {
  const layout = style.layout;
  const gap = GAP[layout] ?? GAP.rows;
  const sizes = aspects.map((aspect, i) =>
    framedSize(aspect, style.sizes?.[i] ?? DEFAULT_PRINT_SIZE, style)
  );

  if (layout === "lead" && sizes.length > 2) {
    const lead = sizes[0];
    const rest = sizes.slice(1);
    const grid = hangRows(
      rest,
      rowWidthFor(rest, rowCountFor(rest.length, style.perRow), gap),
      gap
    );
    const height = Math.max(lead.h + PLACARD, grid.height);
    const restX = lead.w + gap * 2;
    const leadBox = box(0, lead, 0, (height - lead.h - PLACARD) / 2);
    const restBoxes = grid.boxes.map((b) =>
      shift({ ...b, index: b.index + 1 }, restX, (height - grid.height) / 2)
    );
    return {
      width: restX + grid.width,
      height,
      boxes: [leadBox, ...restBoxes],
    };
  }

  const rowCount =
    layout === "rows" ? rowCountFor(sizes.length, style.perRow) : 1;
  const maxWidth =
    rowCount === 1
      ? Number.POSITIVE_INFINITY
      : rowWidthFor(sizes, rowCount, gap);
  return hangRows(sizes, maxWidth, gap);
}

// aspects: width/height of each print, in hanging order; style: a resolved
// hang (see resolveHang). Returns, in inches:
//   { width, height, boxes, hangWidth, floorY?, bench? }
// boxes: [{ index, x, y, w, h, frame, mat, print, placardY }].
export function layoutWall(aspects, style) {
  if (!aspects.length) {
    return { width: 0, height: 0, boxes: [], hangWidth: 0 };
  }
  if (style.mode === "spreads") {
    return layoutBook(aspects, style);
  }
  const group = arrange(aspects, style);

  if (!style.physical) {
    return {
      width: group.width + DIGITAL_MARGIN * 2,
      height: group.height + DIGITAL_MARGIN * 2,
      hangWidth: group.width,
      boxes: group.boxes.map((b) => shift(b, DIGITAL_MARGIN, DIGITAL_MARGIN)),
    };
  }

  // Centre the group on the 57" line, but keep it clear of the bench.
  const bottomAboveFloor = Math.max(
    CENTERLINE - group.height / 2,
    BENCH.h + BENCH_CLEARANCE
  );
  const floorY = MARGIN_TOP + bottomAboveFloor + group.height;
  const width = Math.max(group.width, BENCH.w) + MARGIN_X * 2;
  const offsetX = (width - group.width) / 2;

  return {
    width,
    height: floorY + FLOOR,
    floorY,
    hangWidth: group.width,
    bench: {
      x: (width - BENCH.w) / 2,
      y: floorY - BENCH.h,
      w: BENCH.w,
      h: BENCH.h,
    },
    boxes: group.boxes.map((b) => shift(b, offsetX, MARGIN_TOP)),
  };
}

// --- book ----------------------------------------------------------------------

const PAGE_HEIGHT = 30; // abstract units; only proportions matter
const PAGE_MARGIN = 0.1; // of the page's shorter side, around an image
const BOOK_GAP_X = 8;
const BOOK_GAP_Y = 5;
const BOOK_MARGIN = 8;

// Largest box of `aspect` inside (w × h), centred at (x, y).
function fit(aspect, x, y, w, h) {
  const fw = Math.min(w, h * aspect);
  const fh = fw / aspect;
  return { x: x + (w - fw) / 2, y: y + (h - fh) / 2, w: fw, h: fh };
}

// A book laid open, spread by spread, in rows (style.perRow spreads per row,
// default 3), with the cover first when there is one. Returns the same shape
// as layoutWall plus:
//   pages: [{ x, y, w, h }]           every page (paper)
//   cover: { page, print } | null     the cover page and its image box
// Boxes carry no frame or mat; a box's x/w is the page (or spread) its number
// is centred under.
export function layoutBook(aspects, style) {
  const pageH = PAGE_HEIGHT;
  const pageW =
    pageH * (BOOK_FORMATS[style.bookFormat] ?? BOOK_FORMATS.portrait);
  const spreadW = pageW * 2;
  const margin = Math.min(pageW, pageH) * PAGE_MARGIN;
  const perRow = style.perRow ?? 3;
  const cellH = pageH + PLACARD + BOOK_GAP_Y;

  const items = [];
  if (style.coverImage) {
    items.push({ cover: true });
  }
  style.spreads.forEach((spread) => items.push({ spread }));

  const columns = Math.min(perRow, items.length);
  const width =
    BOOK_MARGIN * 2 + columns * spreadW + (columns - 1) * BOOK_GAP_X;
  const rows = Math.ceil(items.length / perRow);
  const height = BOOK_MARGIN * 2 + rows * cellH - BOOK_GAP_Y;

  const pages = [];
  const boxes = [];
  let cover = null;

  items.forEach((item, n) => {
    const x = BOOK_MARGIN + (n % perRow) * (spreadW + BOOK_GAP_X);
    const y = BOOK_MARGIN + Math.floor(n / perRow) * cellH;
    const left = { x, y, w: pageW, h: pageH };
    const right = { x: x + pageW, y, w: pageW, h: pageH };
    const inner = (page) => [
      page.x + margin,
      page.y + margin,
      page.w - margin * 2,
      page.h - margin * 2,
    ];
    const place = (index, area, print) =>
      boxes.push({
        index,
        x: area.x,
        y: area.y,
        w: area.w,
        h: area.h,
        frame: 0,
        mat: 0,
        print,
        placardY: y + pageH,
      });

    if (item.cover) {
      // A closed book: the front cover alone, where a right page would be.
      pages.push(right);
      cover = {
        page: right,
        print: fit(aspectOf(style.coverImage), ...inner(right)),
        placardY: y + pageH,
      };
      return;
    }

    pages.push(left, right);
    const { indexes, side } = item.spread;
    if (indexes.length === 2) {
      place(indexes[0], left, fit(aspects[indexes[0]], ...inner(left)));
      place(indexes[1], right, fit(aspects[indexes[1]], ...inner(right)));
    } else if (side === "full") {
      const spreadArea = { x, y, w: spreadW, h: pageH };
      place(
        indexes[0],
        spreadArea,
        fit(aspects[indexes[0]], ...inner(spreadArea))
      );
    } else {
      const page = side === "left" ? left : right;
      place(indexes[0], page, fit(aspects[indexes[0]], ...inner(page)));
    }
  });

  boxes.sort((a, b) => a.index - b.index);
  return { width, height, hangWidth: width, boxes, pages, cover };
}

// Percent helpers for absolutely-positioned elements on a wall of
// `wall.width` × `wall.height` inches.
export function percentRect(rect, wall) {
  return {
    left: (rect.x / wall.width) * 100,
    top: (rect.y / wall.height) * 100,
    width: (rect.w / wall.width) * 100,
    height: (rect.h / wall.height) * 100,
  };
}
