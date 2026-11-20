import { module, test } from "qunit";
import {
  aspectOf,
  layoutWall,
  positionsFromLayout,
  presentationMode,
  resolveHang,
  resolveOrders,
  serializeHang,
  serializeOrders,
  snapPosition,
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

// The photographer's proposed orders: named rearrangements of the same
// images, valid only while they still cover exactly the current images.
module("Unit | NPN Submissions | proposed orders", function () {
  const images = [1, 2, 3].map((id) => ({ upload_id: id }));
  const saved = {
    order_name: "As shot",
    orders: [
      { name: "Reversed", ids: [3, 2, 1] },
      { ids: [1, 2] }, // incomplete: dropped
      { ids: [2, 1, 3] },
      { ids: [1, 3, 2] }, // over the limit: dropped
    ],
  };

  test("keeps the main order first and up to two valid alternatives", function (assert) {
    const orders = resolveOrders(saved, "gallery", images);
    assert.deepEqual(orders, [
      { name: "As shot", indexes: [0, 1, 2] },
      { name: "Reversed", indexes: [2, 1, 0] },
      { name: "Option C", indexes: [1, 0, 2] },
    ]);
    assert.deepEqual(serializeOrders(orders, images), {
      order_name: "As shot",
      orders: [
        { name: "Reversed", ids: [3, 2, 1] },
        { name: "Option C", ids: [2, 1, 3] },
      ],
    });
  });

  test("a book or a selection has only its main order", function (assert) {
    assert.strictEqual(resolveOrders(saved, "book", images).length, 1);
    assert.strictEqual(resolveOrders(saved, "lwfull", images).length, 1);
    assert.strictEqual(resolveOrders(null, "gallery", images).length, 1);
  });
});

// A salon hang: every print placed by hand, starting from where it hung.
module("Unit | NPN Submissions | salon hang", function () {
  const images = [1.5, 0.8, 1].map((aspect, i) => ({
    upload_id: 10 + i,
    width: aspect * 1000,
    height: 1000,
  }));
  const aspects = images.map(aspectOf);

  test("starts from the current layout without moving anything", function (assert) {
    const rows = resolveHang({ layout: "rows" }, "gallery", images);
    const before = layoutWall(aspects, rows);
    const positions = positionsFromLayout(before);
    const after = layoutWall(aspects, { ...rows, layout: "free", positions });

    assert.true(after.free);
    after.boxes.forEach((box, i) => {
      assert.strictEqual(Math.round(box.x), Math.round(before.boxes[i].x));
      assert.strictEqual(Math.round(box.w), Math.round(before.boxes[i].w));
    });
  });

  test("saves positions by upload and reads them back", function (assert) {
    const hang = resolveHang(
      { layout: "free", positions: { 10: [50, 57], 11: ["x", 1] } },
      "gallery",
      images
    );
    assert.deepEqual(hang.positions, [[50, 57], null, null]);
    assert.deepEqual(serializeHang(hang, images, null).positions, {
      10: [50, 57],
    });
    // Prints without a position line up to the right of the placed ones.
    const wall = layoutWall(aspects, hang);
    assert.true(wall.boxes[1].x > wall.boxes[0].x + wall.boxes[0].w);
    assert.true(wall.boxes[2].x > wall.boxes[1].x + wall.boxes[1].w);
  });

  test("is only for a physical show", function (assert) {
    assert.notStrictEqual(
      resolveHang({ layout: "free" }, "web", images).layout,
      "free"
    );
    assert.strictEqual(
      resolveOrders(
        { layout: "free", orders: [{ ids: [12, 11, 10] }] },
        "gallery",
        images
      ).length,
      1
    );
  });

  test("snaps to the centerline and to a neighbour", function (assert) {
    const neighbour = { cx: 60, cy: 57, w: 28, h: 22 };
    const nearLine = snapPosition(100, 56, 28, 22, [neighbour]);
    assert.strictEqual(nearLine.cy, 57);
    assert.strictEqual(nearLine.guideY, 57);
    assert.strictEqual(
      nearLine.cx,
      100,
      "x is left alone when nothing is near"
    );

    // Just right of the neighbour: snaps to the standard 5 in gap.
    const beside = snapPosition(93.5, 40, 28, 22, [neighbour]);
    assert.strictEqual(beside.cx, 60 + 14 + 5 + 14);
    assert.strictEqual(beside.guideX, 79);
  });
});
