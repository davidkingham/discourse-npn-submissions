import { loadImage, uploadCanvas } from "./npn-sequence-sheet";
import { aspectOf, FRAMES, layoutWall, MATS, WALLS } from "./npn-wall-layout";

// Draws a hang (see npn-wall-layout) as ONE image — wall, floor line, bench,
// framed and matted prints at their real sizes, placard numbers — and
// uploads it. The project post shows this image where the Project Overview
// used to be, so emails, link previews and the topic thumbnail carry the
// real hang; on the site the interactive wall is mounted over it.

const TARGET_WIDTH = 1600;
const MAX_HEIGHT = 1400;
const FONT =
  "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif";

export function drawHang(images, loaded, hang) {
  const wall = layoutWall(images.map(aspectOf), hang);
  const scale = Math.min(TARGET_WIDTH / wall.width, MAX_HEIGHT / wall.height);
  const px = (inches) => inches * scale;

  const canvas = document.createElement("canvas");
  canvas.width = Math.round(px(wall.width));
  canvas.height = Math.round(px(wall.height));
  const ctx = canvas.getContext("2d");
  ctx.imageSmoothingQuality = "high";

  const colors = WALLS[hang.wall];
  ctx.fillStyle = colors.color;
  ctx.fillRect(0, 0, canvas.width, canvas.height);

  if (wall.floorY !== undefined) {
    ctx.fillStyle = colors.floor;
    ctx.fillRect(0, px(wall.floorY), canvas.width, canvas.height);
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

    const label = images[box.index].number;
    ctx.fillStyle = colors.dark ? "rgba(255,255,255,0.75)" : "rgba(0,0,0,0.6)";
    ctx.font = `600 ${Math.max(16, px(2.6))}px ${FONT}`;
    ctx.textAlign = "center";
    ctx.textBaseline = "top";
    ctx.fillText(label, px(box.x + box.w / 2), px(box.placardY + 0.5));
  });

  return canvas;
}

// images: [{ number, url, width, height }] in hanging order; hang: resolved.
// Resolves to the upload record of the drawn image.
export async function createHangImage(images, hang) {
  const loaded = await Promise.all(
    images.map((image) => loadImage(image.sheet_url || image.url))
  );
  const canvas = drawHang(images, loaded, hang);
  const { upload } = await uploadCanvas(canvas, "exhibition");
  return upload;
}
