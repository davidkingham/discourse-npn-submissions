import { module, test } from "qunit";
import { formatPhotoMetadata } from "discourse/plugins/discourse-npn-submissions/discourse/lib/npn-exif";

module("Unit | NPN Submissions | exif", function () {
  test("a lens the camera could not identify is left out", function (assert) {
    const exif = { make: "NIKON CORPORATION", model: "NIKON Z 8", iso: 64 };
    ["0.0 mm f/0.0", "0.00 mm f/0.0", "0mm f/0"].forEach((lensModel) => {
      assert.strictEqual(
        formatPhotoMetadata({ ...exif, lensModel }),
        "Camera: NIKON Z 8\nISO: 64",
        lensModel
      );
    });
    assert.strictEqual(
      formatPhotoMetadata({ ...exif, lensModel: "NIKKOR Z 24-70mm f/4 S" }),
      "Camera: NIKON Z 8\nLens: NIKKOR Z 24-70mm f/4 S\nISO: 64"
    );
  });
});
