import lightbox from "discourse/lib/lightbox";
import { numberLabel } from "./npn-sequence";

// "View the project": steps through a project's images full-screen, one at a
// time and in order — the way a reader meets a body of work — using
// Discourse's own PhotoSwipe lightbox. Built from a hidden set of
// `.lightbox` anchors so it works anywhere (the critique workspace, the OP's
// Project Overview) without depending on how a post happened to be cooked.

const sources = new Map();

function sourceFor(images) {
  const key = images.map((image) => image.upload_id).join(",");
  if (sources.has(key)) {
    return sources.get(key);
  }

  const container = document.createElement("div");
  container.className = "npn-project-viewer-source";
  container.hidden = true;

  const total = images.filter((i) => !i.number.startsWith("A")).length;
  images.forEach((image) => {
    const anchor = document.createElement("a");
    anchor.className = "lightbox";
    anchor.href = image.url;
    anchor.dataset.largeSrc = image.url;
    if (image.original_width && image.original_height) {
      anchor.dataset.targetWidth = image.original_width;
      anchor.dataset.targetHeight = image.original_height;
    }
    const position = image.number.startsWith("A")
      ? numberLabel(image.number)
      : `${numberLabel(image.number)} of ${total}`;
    anchor.title = image.caption ? `${position}: ${image.caption}` : position;

    const img = document.createElement("img");
    img.src = image.sheet_url || image.url;
    img.alt = numberLabel(image.number);
    // Dimensions for the lightbox's zoom/fit maths.
    if (image.original_width && image.original_height) {
      img.setAttribute("width", image.original_width);
      img.setAttribute("height", image.original_height);
    }
    anchor.appendChild(img);
    container.appendChild(anchor);
  });

  document.body.appendChild(container);
  sources.set(key, container);
  return container;
}

// images: numbered project images in viewing order; startIndex into that list.
export async function openProjectViewer(images, startIndex = 0) {
  if (!images?.length) {
    return;
  }
  const container = sourceFor(images);
  await lightbox(container);
  const anchors = container.querySelectorAll(".lightbox");
  (anchors[startIndex] || anchors[0])?.click();
}
