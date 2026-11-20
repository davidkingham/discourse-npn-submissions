import { module, test } from "qunit";
import {
  compactCameraLine,
  foldInDepthFields,
  mergeTechnicalDetails,
} from "discourse/plugins/discourse-npn-submissions/discourse/lib/npn-photo-form";

// These helpers shape what the photo-first form sends to the server: the
// camera data caption, the merged Technical Details answer, and the single
// story box that replaces In-Depth's three.
module("Unit | NPN Submissions | photo form", function () {
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
