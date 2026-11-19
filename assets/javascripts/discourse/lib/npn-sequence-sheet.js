import { ajax } from "discourse/lib/ajax";

// Renders project-critique graphics as ONE contact-sheet image (numbered
// tiles at their true proportions) and uploads it, so a reply carries a single
// compact picture instead of a dozen inline images:
//
// - createSequenceSheet: a suggested order (one untitled group).
// - createEditSheet: a suggested edit (titled groups: Strongest / Keep /
//   Unsure / Cut / Bring in).
//
// Same approach as discourse-npn-critique-reply's visual notes (canvas →
// toBlob → /uploads.json), which already works against this site's upload
// storage: images are loaded with crossOrigin="anonymous" so the canvas isn't
// tainted.

const SHEET = Object.freeze({
  width: 1200,
  padding: 40,
  gapX: 24,
  gapY: 28,
  // EVERY row uses this height (rows are left-aligned, not stretched to fill
  // the width), so image sizes stay comparable across the whole sheet — a
  // pano reads as wide and a vertical as narrow wherever they sit. Only an
  // image too wide for the sheet on its own is shrunk to fit.
  rowHeight: 200,
  titleSize: 34,
  titleGap: 28,
  headingSize: 30,
  headingGap: 16,
  groupGap: 40,
  // Large: the sheet is shown at ~690px in posts and ~340px on phones.
  labelSize: 36,
  labelGap: 12,
  background: "#ffffff",
  text: "#222222",
  alternate: "#2f6fb3",
  border: "#d6d6d6",
  font: "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif",
});

// Edit sheets carry several groups, so their tiles are a little smaller.
const EDIT_ROW_HEIGHT = 150;

function loadImage(url) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.crossOrigin = "anonymous";
    img.decoding = "async";
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error(`project sheet: load failed ${url}`));
    img.src = url;
  });
}

function aspectOf(item) {
  const w = item.img.naturalWidth || item.image.width || 1;
  const h = item.img.naturalHeight || item.image.height || 1;
  return w / h;
}

// Rows at a fixed height: add images left to right until the next one would
// overflow the width, then start a new row. Returns rows of
// { index, w, h }. An image wider than the sheet on its own is scaled down.
export function layoutRows(aspects, opts = SHEET) {
  const inner = opts.width - opts.padding * 2;
  const rows = [];
  let current = [];
  let used = 0;

  aspects.forEach((aspect, index) => {
    let h = opts.rowHeight;
    let w = aspect * h;
    if (w > inner) {
      w = inner;
      h = inner / aspect;
    }
    const needed = (current.length ? opts.gapX : 0) + w;
    if (current.length && used + needed > inner) {
      rows.push(current);
      current = [];
      used = 0;
    }
    used += (current.length ? opts.gapX : 0) + w;
    current.push({ index, w, h });
  });
  if (current.length) {
    rows.push(current);
  }
  return rows;
}

function rowHeightOf(row) {
  return Math.max(...row.map((cell) => cell.h));
}

function rowWidthOf(row, opts) {
  return (
    row.reduce((sum, cell) => sum + Math.round(cell.w), 0) +
    opts.gapX * (row.length - 1)
  );
}

// groups: [{ heading?, color?, items: [{ image, img }] }]
function drawSheet({ title, groups, rowHeight = SHEET.rowHeight }) {
  const o = { ...SHEET, rowHeight };
  const labelBlock = o.labelGap + o.labelSize;
  const headingBlock = o.headingSize + o.headingGap;
  const titleBlock = title ? o.titleSize + o.titleGap : 0;

  const laidOut = groups
    .filter((group) => group.items.length)
    .map((group) => {
      const rows = layoutRows(group.items.map(aspectOf), o);
      const rowsHeight =
        rows.reduce((sum, row) => sum + rowHeightOf(row) + labelBlock, 0) +
        o.gapY * Math.max(rows.length - 1, 0);
      return {
        ...group,
        rows,
        height: (group.heading ? headingBlock : 0) + rowsHeight,
      };
    });

  const height = Math.round(
    o.padding * 2 +
      titleBlock +
      laidOut.reduce((sum, g) => sum + g.height, 0) +
      o.groupGap * Math.max(laidOut.length - 1, 0)
  );

  // Trim to the content: the widest row, heading or title, so a sheet with
  // short rows isn't padded with empty space and displays larger.
  const canvas = document.createElement("canvas");
  const measure = canvas.getContext("2d");
  measure.font = `600 ${o.titleSize}px ${o.font}`;
  let contentWidth = title ? measure.measureText(title).width : 0;
  measure.font = `600 ${o.headingSize}px ${o.font}`;
  laidOut.forEach((group) => {
    if (group.heading) {
      contentWidth = Math.max(
        contentWidth,
        measure.measureText(group.heading).width
      );
    }
    group.rows.forEach((row) => {
      contentWidth = Math.max(contentWidth, rowWidthOf(row, o));
    });
  });
  contentWidth = Math.min(contentWidth, o.width - o.padding * 2);

  canvas.width = Math.ceil(contentWidth + o.padding * 2);
  canvas.height = height;
  const ctx = canvas.getContext("2d");
  ctx.fillStyle = o.background;
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  ctx.imageSmoothingQuality = "high";
  ctx.textBaseline = "top";

  let y = o.padding;
  if (title) {
    ctx.fillStyle = o.text;
    ctx.font = `600 ${o.titleSize}px ${o.font}`;
    ctx.textAlign = "left";
    ctx.fillText(title, o.padding, y, contentWidth);
    y += titleBlock;
  }

  laidOut.forEach((group, groupIndex) => {
    if (group.heading) {
      ctx.fillStyle = group.color || o.text;
      ctx.font = `600 ${o.headingSize}px ${o.font}`;
      ctx.textAlign = "left";
      ctx.fillText(group.heading, o.padding, y, contentWidth);
      y += headingBlock;
    }

    group.rows.forEach((row, rowIndex) => {
      let x = o.padding;
      const rowH = rowHeightOf(row);
      row.forEach((cell) => {
        const item = group.items[cell.index];
        const w = Math.round(cell.w);
        const h = Math.round(cell.h);
        // Bottom-align within the row so a shrunk pano sits on the same line.
        const top = y + Math.round(rowH - h);
        ctx.drawImage(item.img, x, top, w, h);
        ctx.strokeStyle = o.border;
        ctx.lineWidth = 1;
        ctx.strokeRect(x + 0.5, top + 0.5, w - 1, h - 1);

        const isAlternate = item.image.number.startsWith("A");
        ctx.fillStyle = isAlternate ? o.alternate : o.text;
        ctx.font = `600 ${o.labelSize}px ${o.font}`;
        ctx.textAlign = "center";
        ctx.fillText(item.image.number, x + w / 2, y + rowH + o.labelGap, w);

        x += w + o.gapX;
      });
      y += rowH + labelBlock;
      if (rowIndex < group.rows.length - 1) {
        y += o.gapY;
      }
    });

    if (groupIndex < laidOut.length - 1) {
      y += o.groupGap;
    }
  });

  return canvas;
}

function canvasToBlob(canvas, type, quality) {
  return new Promise((resolve, reject) => {
    try {
      canvas.toBlob(
        (blob) => resolve(blob && blob.size > 0 ? blob : null),
        type,
        quality
      );
    } catch (e) {
      // SecurityError: canvas tainted by a cross-origin image without CORS.
      reject(e);
    }
  });
}

async function loadGroups(groups) {
  return Promise.all(
    groups.map(async (group) => ({
      ...group,
      items: await Promise.all(
        group.images.map(async (image) => ({
          image,
          img: await loadImage(image.sheet_url || image.url),
        }))
      ),
    }))
  );
}

async function uploadCanvas(canvas, basename) {
  let blob = await canvasToBlob(canvas, "image/jpeg", 0.88);
  let ext = "jpg";
  if (!blob) {
    blob = await canvasToBlob(canvas, "image/png");
    ext = "png";
  }
  if (!blob) {
    throw new Error("project sheet: could not encode image");
  }

  const formData = new FormData();
  formData.append("file", blob, `${basename}.${ext}`);
  formData.append("upload_type", "composer");
  formData.append("synchronous", "true");
  const upload = await ajax("/uploads.json", {
    type: "POST",
    data: formData,
    processData: false,
    contentType: false,
  });

  return { upload, width: canvas.width, height: canvas.height };
}

// images: [{ number, url, sheet_url?, width, height }] in sequence order.
// Resolves to { upload, width, height } of the uploaded sheet.
export async function createSequenceSheet({ images, label }) {
  const groups = await loadGroups([{ images }]);
  const canvas = drawSheet({ title: label, groups });
  return uploadCanvas(canvas, "suggested-sequence");
}

// groups: [{ heading, color?, images: [...] }] in display order; empty groups
// are skipped. Resolves to { upload, width, height } of the uploaded sheet.
export async function createEditSheet({ groups, title }) {
  const loaded = await loadGroups(groups);
  const canvas = drawSheet({
    title,
    groups: loaded,
    rowHeight: EDIT_ROW_HEIGHT,
  });
  return uploadCanvas(canvas, "suggested-edit");
}
