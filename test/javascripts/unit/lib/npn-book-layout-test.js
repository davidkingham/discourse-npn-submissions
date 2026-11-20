import { module, test } from "qunit";
import {
  aspectOf,
  layoutWall,
  presentationMode,
  resolveHang,
  serializeHang,
} from "discourse/plugins/discourse-npn-submissions/discourse/lib/npn-wall-layout";

// A book project: spreads follow the order of the images; the saved plan is
// honoured only where it still matches that order.
module("Unit | NPN Submissions | book spreads", function () {
  const images = [1.5, 0.8, 1, 2.4, 0.67].map((aspect, i) => ({
    upload_id: 10 + i,
    width: aspect * 1000,
    height: 1000,
  }));
  const alternate = { upload_id: 99, width: 800, height: 1000 };
  const pool = [...images, alternate];

  test("only a book plans spreads", function (assert) {
    assert.strictEqual(presentationMode("book"), "spreads");
    assert.strictEqual(presentationMode("magazine"), "sequence");
  });

  test("defaults to one image per spread, on the right", function (assert) {
    const hang = resolveHang(null, "book", images);
    assert.strictEqual(hang.bookFormat, "portrait");
    assert.strictEqual(hang.coverImage, null);
    assert.deepEqual(
      hang.spreads,
      images.map((_, i) => ({ indexes: [i], side: "right" }))
    );
  });

  test("keeps saved pairs, sides and cover while they match the order", function (assert) {
    const saved = {
      book_format: "square",
      cover: 99,
      spreads: [
        { ids: [10, 11] },
        { ids: [12], side: "full" },
        // 13 is no longer followed by 99, so this pair falls apart.
        { ids: [13, 99] },
      ],
    };
    const hang = resolveHang(saved, "book", images, pool);
    assert.strictEqual(hang.bookFormat, "square");
    assert.strictEqual(hang.coverImage, alternate);
    assert.deepEqual(hang.spreads, [
      { indexes: [0, 1], side: null },
      { indexes: [2], side: "full" },
      { indexes: [3], side: "right" },
      { indexes: [4], side: "right" },
    ]);

    const out = serializeHang(hang, images, saved);
    assert.strictEqual(out.cover, 99);
    assert.deepEqual(out.spreads, [
      { ids: [10, 11] },
      { ids: [12], side: "full" },
      { ids: [13], side: "right" },
      { ids: [14], side: "right" },
    ]);
  });

  test("lays out pages, a cover, and every image inside its page", function (assert) {
    const hang = resolveHang(
      { cover: 99, spreads: [{ ids: [10, 11] }, { ids: [12], side: "full" }] },
      "book",
      images,
      pool
    );
    const wall = layoutWall(images.map(aspectOf), hang);

    // 4 spreads × 2 pages + the cover page.
    assert.strictEqual(wall.pages.length, 9);
    assert.true(!!wall.cover);
    assert.deepEqual(
      wall.boxes.map((b) => b.index),
      [0, 1, 2, 3, 4]
    );
    wall.boxes.forEach((box) => {
      assert.true(box.print.x >= box.x, "left edge inside");
      assert.true(box.print.y >= box.y, "top edge inside");
      assert.true(
        box.print.x + box.print.w <= box.x + box.w + 0.001,
        "right edge inside"
      );
      assert.true(
        box.print.y + box.print.h <= box.y + box.h + 0.001,
        "bottom edge inside"
      );
    });
    // A facing pair sits on two different pages of the same spread.
    assert.strictEqual(wall.boxes[0].y, wall.boxes[1].y);
    assert.true(wall.boxes[1].x > wall.boxes[0].x);
    // An image across both pages gets the whole spread to sit in.
    assert.strictEqual(wall.boxes[2].w, wall.boxes[0].w * 2);
  });
});
