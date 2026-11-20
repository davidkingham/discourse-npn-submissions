import { RANKS } from "./npn-hang-suggestion";
import { loadScaledImages, uploadCanvas } from "./npn-sequence-sheet";
import { aspectOf, FRAMES, layoutWall, MATS, WALLS } from "./npn-wall-layout";

// Draws a hang (see npn-wall-layout) as ONE image — wall, floor line, bench,
// framed and matted prints at their real sizes, placard numbers — and
// uploads it.
//
// - The photographer's hang goes in the project post where the Project
//   Overview used to be, so emails, link previews and the topic thumbnail
//   carry the real hang; on the site the interactive wall is mounted over it.
// - A critic's suggested hang adds an optional title, ranking marks on the
//   placards (★ ✓ ?), and a "Left out" strip under the wall.

const TARGET_WIDTH = 1600;
const MAX_HEIGHT = 1400;
const TITLE_HEIGHT = 64;
const LEFT_OUT_THUMB = 96;
const LEFT_OUT_PAD = 24;
const FONT =
  "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif";

function measureLeftOut(items, width) {
  // Thumbs in rows at a fixed height, left to right.
  const rows = [[]];
  let x = LEFT_OUT_PAD;
  items.forEach((item) => {
    const w = LEFT_OUT_THUMB * aspectOf(item.image);
    if (x + w > width - LEFT_OUT_PAD && rows.at(-1).length) {
      rows.push([]);
      x = LEFT_OUT_PAD;
    }
    rows.at(-1).push({ ...item, x, w });
    x += w + 16;
  });
  return rows;
}

// options: { marks: { number: rank }, leftOut: [{ image, img }],
//            title, leftOutLabel }
export function drawHang(images, loaded, hang, options = {}) {
  const wall = layoutWall(images.map(aspectOf), hang);
  const scale = Math.min(TARGET_WIDTH / wall.width, MAX_HEIGHT / wall.height);
  const px = (inches) => inches * scale;
  const wallW = Math.round(px(wall.width));
  const wallH = Math.round(px(wall.height));

  const title = options.title?.trim();
  const titleH = title ? TITLE_HEIGHT : 0;
  const leftOut = options.leftOut ?? [];
  const leftOutRows = leftOut.length ? measureLeftOut(leftOut, wallW) : [];
  const rowH = LEFT_OUT_THUMB + 40;
  const leftOutH = leftOutRows.length
    ? LEFT_OUT_PAD * 2 + 34 + leftOutRows.length * rowH
    : 0;

  const canvas = document.createElement("canvas");
  canvas.width = wallW;
  canvas.height = titleH + wallH + leftOutH;
  const ctx = canvas.getContext("2d");
  ctx.imageSmoothingQuality = "high";

  const colors = WALLS[hang.wall];
  const ink = colors.dark ? "rgba(255,255,255,0.8)" : "rgba(0,0,0,0.65)";

  // Title band (a critic's label: "Option A").
  if (titleH) {
    ctx.fillStyle = colors.color;
    ctx.fillRect(0, 0, wallW, titleH);
    ctx.fillStyle = ink;
    ctx.font = `600 30px ${FONT}`;
    ctx.textAlign = "left";
    ctx.textBaseline = "middle";
    ctx.fillText(title, 28, titleH / 2 + 6, wallW - 56);
  }

  ctx.save();
  ctx.translate(0, titleH);

  ctx.fillStyle = colors.color;
  ctx.fillRect(0, 0, wallW, wallH);

  if (wall.floorY !== undefined) {
    ctx.fillStyle = colors.floor;
    ctx.fillRect(0, px(wall.floorY), wallW, wallH);
  }

  if (wall.bench) {
    const b = wall.bench;
    ctx.fillStyle = colors.dark ? "rgba(255,255,255,0.14)" : "rgba(0,0,0,0.16)";
    ctx.fillRect(px(b.x), px(b.y), px(b.w), px(3));
    ctx.fillRect(px(b.x + 3), px(b.y + 3), px(2.5), px(15));
    ctx.fillRect(px(b.x + 42.5), px(b.y + 3), px(2.5), px(15));
  }

  const mat = MATS[hang.mat];
  const frame = FRAMES[hang.frame];
  const labelSize = Math.max(16, px(2.6));
  wall.boxes.forEach((box) => {
    // Shadow under the frame (or the bare print) so it sits on the wall.
    ctx.save();
    ctx.shadowColor = "rgba(0,0,0,0.3)";
    ctx.shadowBlur = px(1.2);
    ctx.shadowOffsetY = px(0.5);
    ctx.fillStyle = frame || mat || "#000";
    ctx.fillRect(px(box.x), px(box.y), px(box.w), px(box.h));
    ctx.restore();

    if (mat) {
      ctx.fillStyle = mat;
      ctx.fillRect(
        px(box.x + box.frame),
        px(box.y + box.frame),
        px(box.w - box.frame * 2),
        px(box.h - box.frame * 2)
      );
    }

    const p = box.print;
    ctx.drawImage(loaded[box.index], px(p.x), px(p.y), px(p.w), px(p.h));

    // Placard: optional rank mark, then the number.
    const number = images[box.index].number;
    const rank = RANKS.find((r) => r.key === options.marks?.[number]);
    ctx.font = `600 ${labelSize}px ${FONT}`;
    ctx.textBaseline = "top";
    const text = rank ? `${rank.symbol} ${number}` : number;
    const textW = ctx.measureText(text).width;
    let tx = px(box.x + box.w / 2) - textW / 2;
    const ty = px(box.placardY + 0.5);
    ctx.textAlign = "left";
    if (rank) {
      ctx.fillStyle = rank.color;
      ctx.fillText(rank.symbol, tx, ty);
      tx += ctx.measureText(`${rank.symbol} `).width;
    }
    ctx.fillStyle = number.startsWith("A")
      ? colors.dark
        ? "#9cc3ef"
        : "#2f6fb3"
      : ink;
    ctx.fillText(number, tx, ty);
  });
  ctx.restore();

  // "Left out" strip under the wall.
  if (leftOutH) {
    const top = titleH + wallH;
    ctx.fillStyle = "#f3f2ef";
    ctx.fillRect(0, top, wallW, leftOutH);
    ctx.fillStyle = "#555";
    ctx.font = `600 24px ${FONT}`;
    ctx.textAlign = "left";
    ctx.textBaseline = "top";
    ctx.fillText(options.leftOutLabel || "Left out", LEFT_OUT_PAD, top + 20);
    leftOutRows.forEach((row, r) => {
      const y = top + LEFT_OUT_PAD + 34 + r * rowH;
      row.forEach((item) => {
        ctx.globalAlpha = 0.6;
        ctx.drawImage(item.img, item.x, y, item.w, LEFT_OUT_THUMB);
        ctx.globalAlpha = 1;
        ctx.strokeStyle = "#c8c6c0";
        ctx.strokeRect(item.x + 0.5, y + 0.5, item.w - 1, LEFT_OUT_THUMB - 1);
        ctx.fillStyle = "#c62828";
        ctx.font = `600 22px ${FONT}`;
        ctx.textAlign = "center";
        ctx.fillText(
          `✕ ${item.image.number}`,
          item.x + item.w / 2,
          y + LEFT_OUT_THUMB + 8
        );
      });
    });
  }

  return canvas;
}

function srcOf(image) {
  return image.sheet_url || image.url;
}

// images: [{ number, url, width, height }] in hanging order; hang: resolved.
// Resolves to the upload record of the drawn image. A rejection carries
// error.stage ("load" with error.imageIndex, "draw" or "upload").
export async function createHangImage(images, hang) {
  const loaded = await loadScaledImages(images.map(srcOf));
  const canvas = drawStage(() => drawHang(images, loaded, hang));
  const { upload } = await uploadCanvas(canvas, "exhibition");
  return upload;
}

function drawStage(draw) {
  try {
    return draw();
  } catch (e) {
    e.stage = "draw";
    throw e;
  }
}

// A critic's suggestion: the hung prints (in their order) on the hang, with
// rank marks, a title, and the left-out prints in a strip below.
// Resolves to { upload, width, height }.
export async function createSuggestionImage({
  images,
  hang,
  marks,
  leftOut,
  title,
  leftOutLabel,
}) {
  const out = leftOut ?? [];
  const all = await loadScaledImages([...images, ...out].map(srcOf));
  const loaded = all.slice(0, images.length);
  const leftOutLoaded = out.map((image, index) => ({
    image,
    img: all[images.length + index],
  }));
  const canvas = drawStage(() =>
    drawHang(images, loaded, hang, {
      marks,
      leftOut: leftOutLoaded,
      title,
      leftOutLabel,
    })
  );
  return uploadCanvas(canvas, "suggested-hang");
}
