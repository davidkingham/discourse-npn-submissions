import { module, test } from "qunit";
import {
  buildSuggestionMarkup,
  containsSuggestion,
  findSuggestionByUpload,
  parseSuggestion,
  suggestionKind,
  suggestionSummary,
  suggestionUpload,
} from "discourse/plugins/discourse-npn-submissions/discourse/lib/npn-hang-suggestion";
import { serializeHang } from "discourse/plugins/discourse-npn-submissions/discourse/lib/npn-wall-layout";

// The alt text of a suggestion image is its only stored form: it's what a
// reader of plain-text email sees and what the tool reopens from. These
// tests pin that format.
module("Unit | NPN Submissions | hang suggestion", function () {
  const originals = ["1", "2", "3", "4", "5", "6", "7", "8", "9"];
  const known = new Set([...originals, "A1", "A2"]);
  const image = { short_url: "upload://abc.jpeg", width: 690, height: 400 };

  test("kind follows the presentation goal", function (assert) {
    assert.strictEqual(suggestionKind("gallery"), "hang");
    assert.strictEqual(suggestionKind("web"), "hang");
    assert.strictEqual(suggestionKind(null), "hang");
    assert.strictEqual(suggestionKind("book"), "spreads");
    assert.strictEqual(suggestionKind("magazine"), "sequence");
    assert.strictEqual(suggestionKind("lwfull"), "selection");
    assert.strictEqual(suggestionKind("on"), "selection");
  });

  test("a hang round-trips through its alt text", function (assert) {
    const summary = suggestionSummary({
      kind: "hang",
      order: ["9", "8", "7", "5", "A1"],
      ranks: { 9: "strongest", 8: "keep", 1: "keep" },
      originals,
      layout: "lead",
      layoutChanged: true,
    });
    assert.strictEqual(
      summary,
      "9, 8, 7, 5, A1 · left out 1, 2, 3, 4, 6 · strongest 9 · keep 8 · lead print"
    );

    const markup = buildSuggestionMarkup({
      kind: "hang",
      label: "Option (A)",
      summary,
      image,
    });
    assert.strictEqual(
      markup,
      `![Suggested hang (Option A): ${summary}|690x400](upload://abc.jpeg)`
    );
    assert.true(containsSuggestion(`Some text\n\n${markup}\n`));
    assert.deepEqual(parseSuggestion(markup, { known, originals }), {
      kind: "hang",
      label: "Option A",
      order: ["9", "8", "7", "5", "A1"],
      ranks: { 8: "keep", 9: "strongest" },
      layout: "lead",
    });
  });

  test("a selection lists what's out and in, not an order", function (assert) {
    const summary = suggestionSummary({
      kind: "selection",
      order: ["1", "2", "4", "9", "A2"],
      ranks: { 9: "strongest" },
      originals,
    });
    assert.strictEqual(
      summary,
      "left out 3, 5, 6, 7, 8 · strongest 9 · bring in A2"
    );
    const markup = buildSuggestionMarkup({ kind: "selection", summary, image });
    assert.deepEqual(parseSuggestion(markup, { known, originals }), {
      kind: "selection",
      label: "",
      order: ["1", "2", "4", "9", "A2"],
      ranks: { 9: "strongest" },
      layout: null,
    });
  });

  test("spreads round-trip with pairs, sides and the cover", function (assert) {
    const book = {
      facing: [["2", "1"]],
      across: ["3"],
      left: ["5"],
      cover: "A1",
    };
    const summary = suggestionSummary({
      kind: "spreads",
      order: ["2", "1", "3", "5"],
      ranks: { 3: "strongest" },
      originals: ["1", "2", "3", "4", "5"],
      book,
    });
    assert.strictEqual(
      summary,
      "2, 1, 3, 5 · left out 4 · strongest 3 · facing 2+1 · across 3 · left page 5 · cover A1"
    );
    const markup = buildSuggestionMarkup({ kind: "spreads", summary, image });
    assert.deepEqual(parseSuggestion(markup, { known, originals }), {
      kind: "spreads",
      label: "",
      order: ["2", "1", "3", "5"],
      ranks: { 3: "strongest" },
      layout: null,
      book,
    });
  });

  test("older suggested-sequence images still reopen", function (assert) {
    assert.deepEqual(
      parseSuggestion(
        "![Suggested sequence (B): 1, 3, A1|690x300](upload://old.jpeg)",
        { known, originals }
      ),
      {
        kind: "sequence",
        label: "B",
        order: ["1", "3", "A1"],
        ranks: {},
        layout: null,
      }
    );
    assert.strictEqual(parseSuggestion("no image here"), null);
  });

  test("only the critic's own earlier image is found", function (assert) {
    const mine = "![Suggested hang: 2, 1|690x400](upload://mine.jpeg)";
    const quoted = "![Suggested hang: 1, 2|690x400](upload://theirs.jpeg)";
    const text = `[quote="other"]\n${quoted}\n[/quote]\n\n${mine}\n`;

    assert.strictEqual(suggestionUpload(mine), "upload://mine.jpeg");
    assert.strictEqual(
      findSuggestionByUpload(text, "upload://mine.jpeg"),
      mine
    );
    assert.strictEqual(
      findSuggestionByUpload(text, "upload://gone.jpeg"),
      null,
      "nothing is matched when the earlier image was deleted"
    );
    assert.strictEqual(findSuggestionByUpload(text, null), null);
  });

  test("a hang keeps the sizes of prints that aren't hung", function (assert) {
    const style = {
      mode: "hang",
      layout: "line",
      wall: "warm",
      mat: "white",
      matWidth: 3,
      frame: "black",
      unit: "in",
      sizes: [24],
    };
    const saved = serializeHang(style, [{ upload_id: 2 }], {
      sizes: { 1: 36, 2: 20 },
    });
    assert.deepEqual(saved.sizes, { 1: 36, 2: 24 });
  });
});
