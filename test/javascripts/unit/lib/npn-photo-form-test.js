import { module, test } from "qunit";
import {
  compactCameraLine,
  focusFromTopics,
  foldInDepthFields,
  mergeTechnicalDetails,
} from "discourse/plugins/discourse-npn-submissions/discourse/lib/npn-photo-form";

// The photo-first form has no Feedback Focus or Critique Style cards, so these
// helpers decide what the server is told. The server requires Technical
// Details for a "technical" focus, which is why the focus rule is pinned here.
module("Unit | NPN Submissions | photo form", function () {
  test("no topics means both", function (assert) {
    assert.strictEqual(focusFromTopics([]), "both");
    assert.strictEqual(focusFromTopics(undefined), "both");
  });

  test("only artistic topics is artistic", function (assert) {
    assert.strictEqual(focusFromTopics(["mood", "composition"]), "artistic");
  });

  test("only technical topics is technical", function (assert) {
    assert.strictEqual(focusFromTopics(["sharpness"]), "technical");
    assert.strictEqual(focusFromTopics(["sharpness", "exposure"]), "technical");
  });

  test("a mix, or a topic that sits in both camps, is both", function (assert) {
    assert.strictEqual(focusFromTopics(["mood", "sharpness"]), "both");
    assert.strictEqual(focusFromTopics(["processing"]), "both");
    assert.strictEqual(focusFromTopics(["sharpness", "color"]), "both");
    assert.strictEqual(focusFromTopics(["mood", "unsure"]), "both");
  });

  test("unknown topics from an older draft are ignored", function (assert) {
    assert.strictEqual(focusFromTopics(["retired_topic"]), "both");
    assert.strictEqual(focusFromTopics(["retired_topic", "mood"]), "artistic");
  });

  test("camera data becomes one caption line", function (assert) {
    assert.strictEqual(
      compactCameraLine(
        "Camera: Canon EOS R5\nLens: RF 24-70mm\nFocal length: 24mm\nShutter speed: 1/60s\nAperture: f/11\nISO: 100\nFlash: Fired"
      ),
      "Canon EOS R5 · RF 24-70mm · 24mm · 1/60s · f/11 · ISO 100 · Flash Fired"
    );
    assert.strictEqual(compactCameraLine(null), "");
    assert.strictEqual(compactCameraLine("Camera: \nISO: 400"), "ISO 400");
  });

  test("camera data leads the typed technical details", function (assert) {
    assert.strictEqual(
      mergeTechnicalDetails("Camera: R5", "Tripod, two frames blended."),
      "Camera: R5\n\nTripod, two frames blended."
    );
    assert.strictEqual(mergeTechnicalDetails("Camera: R5", ""), "Camera: R5");
    assert.strictEqual(mergeTechnicalDetails(null, " Handheld "), "Handheld");
    assert.strictEqual(mergeTechnicalDetails(null, null), "");
  });

  test("camera data already in the text is not doubled", function (assert) {
    const saved = "Camera: R5\n\nTripod.";
    assert.strictEqual(mergeTechnicalDetails("Camera: R5", saved), saved);
  });

  test("In-Depth answers fold into the story", function (assert) {
    assert.deepEqual(
      foldInDepthFields({
        about_this_image: "Dawn at the lake.",
        creative_intent: "The stillness drew me.",
        creative_direction: "Quiet, cool, spare.",
        feedback_requested: "Is it too empty?",
      }),
      {
        about_this_image:
          "Dawn at the lake.\n\nThe stillness drew me.\n\nQuiet, cool, spare.",
        feedback_requested: "Is it too empty?",
      }
    );
  });

  test("folding leaves other drafts alone", function (assert) {
    assert.deepEqual(foldInDepthFields({ feedback_requested: "Thoughts?" }), {
      feedback_requested: "Thoughts?",
    });
    assert.deepEqual(foldInDepthFields(undefined), {});
  });
});
