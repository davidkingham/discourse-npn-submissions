import { module, test } from "qunit";
import {
  colourProfileWarningFor,
  noteColourProfile,
  profileNeedsWarning,
  readEmbeddedProfile,
} from "discourse/plugins/discourse-npn-submissions/discourse/lib/npn-colour-profile";

function bytesOf(...parts) {
  const chunks = parts.map((part) =>
    typeof part === "string"
      ? Uint8Array.from(part, (char) => char.charCodeAt(0))
      : Uint8Array.from(part)
  );
  const out = new Uint8Array(chunks.reduce((sum, c) => sum + c.length, 0));
  let offset = 0;
  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.length;
  }
  return out;
}

function u32(value, littleEndian = false) {
  const bytes = new Uint8Array(4);
  new DataView(bytes.buffer).setUint32(0, value, littleEndian);
  return bytes;
}

function u32le(value) {
  return u32(value, true);
}

function iccProfile(name, { space = "RGB ", version = 2 } = {}) {
  const tag =
    version === 2
      ? bytesOf("desc", u32(0), u32(name.length + 1), name, [0])
      : bytesOf(
          "mluc",
          u32(0),
          u32(1),
          u32(12),
          "enUS",
          u32(name.length * 2),
          u32(28),
          Array.from(name).flatMap((char) => [0, char.charCodeAt(0)])
        );
  const header = new Uint8Array(128);
  header.set(bytesOf(space), 16);
  return bytesOf(header, u32(1), "desc", u32(144), u32(tag.length), tag);
}

function jpegWith(profile) {
  const exif = bytesOf([0xff, 0xe1, 0, 8], "Exif", [0, 0]);
  const length = profile.length + 16;
  return bytesOf(
    [0xff, 0xd8],
    exif,
    [0xff, 0xe2, Math.floor(length / 256), length % 256],
    "ICC_PROFILE",
    [0, 1, 1],
    profile,
    [0xff, 0xda, 0, 2]
  );
}

async function pngWith(profile) {
  const stream = new Blob([profile])
    .stream()
    .pipeThrough(new CompressionStream("deflate"));
  const zipped = new Uint8Array(await new Response(stream).arrayBuffer());
  const body = bytesOf("icc", [0, 0], zipped);
  return bytesOf(
    [0x89],
    "PNG",
    [13, 10, 26, 10],
    u32(13),
    "IHDR",
    new Uint8Array(13),
    u32(0),
    u32(body.length),
    "iCCP",
    body,
    u32(0),
    u32(0),
    "IDAT",
    u32(0)
  );
}

function webpWith(profile) {
  const padding = profile.length % 2 ? [0] : [];
  return bytesOf(
    "RIFF",
    u32le(0),
    "WEBP",
    "VP8X",
    u32le(10),
    new Uint8Array(10),
    "ICCP",
    u32le(profile.length),
    profile,
    padding
  );
}

module("Unit | Lib | npn-colour-profile", function () {
  test("reads the profile name from a JPEG", async function (assert) {
    const profile = await readEmbeddedProfile(
      jpegWith(iccProfile("ProPhoto RGB")).buffer
    );

    assert.deepEqual(
      profile,
      { name: "ProPhoto RGB", space: "RGB" },
      "the ICC v2 description is read past the EXIF block"
    );
  });

  test("reads the profile name from a PNG and a WebP", async function (assert) {
    const v4 = iccProfile("Display P3", { version: 4 });

    assert.strictEqual(
      (await readEmbeddedProfile((await pngWith(v4)).buffer))?.name,
      "Display P3",
      "the compressed PNG profile with an ICC v4 description is read"
    );
    assert.strictEqual(
      (await readEmbeddedProfile(webpWith(v4).buffer))?.name,
      "Display P3",
      "the WebP profile is read"
    );
  });

  test("files without a readable profile report none", async function (assert) {
    const noProfile = bytesOf([0xff, 0xd8, 0xff, 0xda, 0, 2]);
    const truncated = jpegWith(iccProfile("ProPhoto RGB")).slice(0, 60);

    assert.strictEqual(
      await readEmbeddedProfile(noProfile.buffer),
      null,
      "a JPEG with no profile"
    );
    assert.strictEqual(
      await readEmbeddedProfile(truncated.buffer),
      null,
      "a profile cut off mid-way"
    );
    assert.strictEqual(
      await readEmbeddedProfile(bytesOf("not an image").buffer),
      null,
      "a file that is not an image"
    );
  });

  test("only ProPhoto and unrecognised profiles need a warning", function (assert) {
    [
      "sRGB IEC61966-2.1",
      "sRGB built-in",
      "c2",
      "Adobe RGB (1998)",
      "Nikon Adobe RGB 4.0.0.3001",
      "Display P3",
      "Apple Wide Color Sharing Profile",
    ].forEach((name) => {
      assert.false(profileNeedsWarning({ name, space: "RGB" }), name);
    });

    ["ProPhoto RGB", "Generic RGB Profile", "Color LCD"].forEach((name) => {
      assert.true(profileNeedsWarning({ name, space: "RGB" }), name);
    });

    assert.false(
      profileNeedsWarning({ name: "Dot Gain 20%", space: "GRAY" }),
      "grayscale profiles are left alone"
    );
    assert.false(profileNeedsWarning(null), "no profile");
  });

  test("a ProPhoto upload is noted against its upload", async function (assert) {
    const prophoto = new File([jpegWith(iccProfile("ProPhoto RGB"))], "a.jpg");
    const srgb = new File([jpegWith(iccProfile("sRGB IEC61966-2.1"))], "b.jpg");
    const prophotoUpload = { id: 1 };
    const srgbUpload = { id: 2 };

    await noteColourProfile(prophoto, prophotoUpload);
    await noteColourProfile(srgb, srgbUpload);
    await noteColourProfile(prophoto, null);

    assert.strictEqual(
      colourProfileWarningFor(prophotoUpload),
      "ProPhoto RGB",
      "the ProPhoto upload carries its profile name"
    );
    assert.strictEqual(
      colourProfileWarningFor(srgbUpload),
      null,
      "the sRGB upload has no warning"
    );
    assert.strictEqual(
      colourProfileWarningFor({ id: 1 }),
      null,
      "an upload restored from a draft has no warning"
    );
    assert.deepEqual(
      prophotoUpload,
      { id: 1 },
      "nothing is added to the upload that gets saved"
    );
  });
});
