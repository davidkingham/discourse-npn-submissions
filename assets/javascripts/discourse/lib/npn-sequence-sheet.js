import { ajax } from "discourse/lib/ajax";

// Renders a suggested sequence as ONE contact-sheet image (numbered tiles at
// their true proportions, in order) and uploads it, so a reply carries a
// single compact picture instead of a dozen inline images.
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
  // Large: the sheet is shown at ~690px in posts and ~340px on phones.
  labelSize: 36,
  labelGap: 12,
  background: "#ffffff",
  text: "#222222",
  alternate: "#2f6fb3",
  border: "#d6d6d6",
  font: "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif",
});

function loadImage(url) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.crossOrigin = "anonymous";
    img.decoding = "async";
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error(`sequence sheet: load failed ${url}`));
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

function drawSheet({ items, label }) {
  const o = SHEET;
  const rows = layoutRows(items.map(aspectOf), o);
  const labelBlock = o.labelGap + o.labelSize;
  const titleBlock = label ? o.titleSize + o.titleGap : 0;
  const rowsHeight =
    rows.reduce((sum, row) => sum + rowHeightOf(row) + labelBlock, 0) +
    o.gapY * Math.max(rows.length - 1, 0);
  const height = Math.round(o.padding * 2 + titleBlock + rowsHeight);

  // Trim to the content: the widest row (or the title), so a sheet with
  // short rows isn't padded with empty space and displays larger.
  const canvas = document.createElement("canvas");
  const measure = canvas.getContext("2d");
  measure.font = `600 ${o.titleSize}px ${o.font}`;
  const titleWidth = label ? measure.measureText(label).width : 0;
  const rowsWidth = Math.max(
    ...rows.map(
      (row) =>
        row.reduce((sum, cell) => sum + Math.round(cell.w), 0) +
        o.gapX * (row.length - 1)
    )
  );
  const contentWidth = Math.min(
    Math.max(rowsWidth, titleWidth),
    o.width - o.padding * 2
  );
  canvas.width = Math.ceil(contentWidth + o.padding * 2);
  canvas.height = height;
  const ctx = canvas.getContext("2d");
  ctx.fillStyle = o.background;
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  ctx.imageSmoothingQuality = "high";
  ctx.textBaseline = "top";

  let y = o.padding;
  if (label) {
    ctx.fillStyle = o.text;
    ctx.font = `600 ${o.titleSize}px ${o.font}`;
    ctx.textAlign = "left";
    ctx.fillText(label, o.padding, y, contentWidth);
    y += titleBlock;
  }

  rows.forEach((row, rowIndex) => {
    let x = o.padding;
    row.forEach((cell) => {
      const item = items[cell.index];
      const w = Math.round(cell.w);
      const h = Math.round(cell.h);
      // Bottom-align within the row so a shrunk pano sits on the same line.
      const top = y + Math.round(rowHeightOf(row) - h);
      ctx.drawImage(item.img, x, top, w, h);
      ctx.strokeStyle = o.border;
      ctx.lineWidth = 1;
      ctx.strokeRect(x + 0.5, top + 0.5, w - 1, h - 1);

      const isAlternate = item.image.number.startsWith("A");
      ctx.fillStyle = isAlternate ? o.alternate : o.text;
      ctx.font = `600 ${o.labelSize}px ${o.font}`;
      ctx.textAlign = "center";
      ctx.fillText(
        item.image.number,
        x + w / 2,
        y + rowHeightOf(row) + o.labelGap,
        w
      );

      x += w + o.gapX;
    });
    y += rowHeightOf(row) + labelBlock + (rowIndex < rows.length - 1 ? o.gapY : 0);
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

// images: [{ number, url, sheet_url?, width, height }] in sequence order.
// Resolves to { markdownImage, upload } where markdownImage is the
// `![alt|WxH](upload://…)` line for the block.
export async function createSequenceSheet({ images, label }) {
  const loaded = await Promise.all(
    images.map(async (image) => ({
      image,
      img: await loadImage(image.sheet_url || image.url),
    }))
  );
  const canvas = drawSheet({ items: loaded, label });

  let blob = await canvasToBlob(canvas, "image/jpeg", 0.88);
  let ext = "jpg";
  if (!blob) {
    blob = await canvasToBlob(canvas, "image/png");
    ext = "png";
  }
  if (!blob) {
    throw new Error("sequence sheet: could not encode image");
  }

  const formData = new FormData();
  formData.append("file", blob, `suggested-sequence.${ext}`);
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
