// Reads the name of the ICC colour profile embedded in a photo, in the
// browser, so a form can refuse a file in a profile NPN does not accept
// before it is uploaded.
//
// ORIGINAL CODE written for this plugin (MIT, same as the plugin). It follows
// the public JPEG (APP2 "ICC_PROFILE"), PNG (iCCP), WebP (ICCP) and ICC.1
// profile layouts. No third-party source was copied or vendored.
//
// The server makes the real decision (see
// DiscourseNpnSubmissions::ColourProfileUploadExtension, which also explains
// why: ProPhoto RGB and unfamiliar profiles do not look the same in every
// view). This is the same test run early, so the member gets the answer at
// once instead of after the upload.
//
// Fully defensive: missing, truncated or malformed input reads as "no
// profile", and nothing here throws. If in doubt the file goes to the
// server, which checks it again.

import { i18n } from "discourse-i18n";

// Keep in step with ACCEPTED in lib/discourse_npn_submissions/icc_profile.rb.
const ACCEPTED = /srgb|^c2$|adobe\s*rgb|display\s*p3|apple wide color/i;

// Enough to cover the metadata blocks that precede the profile in a JPEG.
const HEAD_BYTES = 1024 * 1024;
const MAX_NAME_LENGTH = 60;

function ascii(bytes, offset, length) {
  let text = "";
  for (let i = 0; i < length && offset + i < bytes.length; i++) {
    const code = bytes[offset + i];
    if (code === 0) {
      break;
    }
    text += String.fromCharCode(code);
  }
  return text;
}

// { name, space } from raw ICC profile bytes, or null.
export function parseIccProfile(bytes) {
  if (!bytes || bytes.length < 132) {
    return null;
  }
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const space = ascii(bytes, 16, 4).trim();
  const tagCount = view.getUint32(128);
  for (let i = 0; i < tagCount; i++) {
    const entry = 132 + i * 12;
    if (entry + 12 > bytes.length) {
      return null;
    }
    if (ascii(bytes, entry, 4) !== "desc") {
      continue;
    }
    const tag = view.getUint32(entry + 4);
    if (tag + 12 > bytes.length) {
      return null;
    }
    const type = ascii(bytes, tag, 4);
    let name = null;
    if (type === "desc") {
      // ICC v2: a length-prefixed ASCII string.
      name = ascii(bytes, tag + 12, view.getUint32(tag + 8));
    } else if (type === "mluc" && tag + 28 <= bytes.length) {
      // ICC v4: localised UTF-16BE strings; the first record is enough.
      const length = view.getUint32(tag + 20);
      const start = tag + view.getUint32(tag + 24);
      if (start + length > bytes.length) {
        return null;
      }
      name = "";
      for (let k = 0; k + 1 < length; k += 2) {
        name += String.fromCharCode(view.getUint16(start + k));
      }
    }
    name = name?.replace(/\0/g, "").trim();
    return name ? { name: name.slice(0, MAX_NAME_LENGTH), space } : null;
  }
  return null;
}

function jpegProfileBytes(bytes) {
  const chunks = [];
  let offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] !== 0xff) {
      return null;
    }
    const marker = bytes[offset + 1];
    if (marker === 0xda || marker === 0xd9) {
      break;
    }
    const length = bytes[offset + 2] * 256 + bytes[offset + 3];
    if (marker === 0xe2 && ascii(bytes, offset + 4, 11) === "ICC_PROFILE") {
      chunks.push({
        order: bytes[offset + 16],
        data: bytes.subarray(offset + 18, offset + 2 + length),
      });
    }
    offset += 2 + length;
  }
  if (!chunks.length) {
    return null;
  }
  chunks.sort((a, b) => a.order - b.order);
  const total = chunks.reduce((sum, chunk) => sum + chunk.data.length, 0);
  const profile = new Uint8Array(total);
  let position = 0;
  for (const chunk of chunks) {
    profile.set(chunk.data, position);
    position += chunk.data.length;
  }
  return profile;
}

// Reads a stream to the end with a plain reader loop. (Not `new Response(
// stream)`: where `fetch` is polyfilled, as in the test suite, Response does
// not accept a stream.)
async function readAll(stream) {
  const reader = stream.getReader();
  const chunks = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) {
      break;
    }
    chunks.push(value);
    total += value.length;
  }
  const out = new Uint8Array(total);
  let position = 0;
  for (const chunk of chunks) {
    out.set(chunk, position);
    position += chunk.length;
  }
  return out;
}

async function inflate(bytes) {
  if (typeof DecompressionStream === "undefined") {
    return null;
  }
  return await readAll(
    new Blob([bytes]).stream().pipeThrough(new DecompressionStream("deflate"))
  );
}

async function pngProfileBytes(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let offset = 8;
  while (offset + 8 <= bytes.length) {
    const length = view.getUint32(offset);
    const type = ascii(bytes, offset + 4, 4);
    const data = offset + 8;
    if (type === "IDAT" || type === "IEND") {
      return null;
    }
    if (type === "iCCP" && data + length <= bytes.length) {
      // Profile name, a zero byte, the compression method, then zlib data.
      let start = data;
      while (start < data + length && bytes[start] !== 0) {
        start++;
      }
      return await inflate(bytes.subarray(start + 2, data + length));
    }
    offset = data + length + 4;
  }
  return null;
}

function webpProfileBytes(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let offset = 12;
  while (offset + 8 <= bytes.length) {
    const length = view.getUint32(offset + 4, true);
    if (ascii(bytes, offset, 4) === "ICCP") {
      return bytes.subarray(offset + 8, offset + 8 + length);
    }
    offset += 8 + length + (length % 2);
  }
  return null;
}

// { name, space } for the profile embedded in the start of an image file, or
// null when there is none (or the format isn't one we read).
export async function readEmbeddedProfile(buffer) {
  try {
    const bytes = new Uint8Array(buffer);
    let profile = null;
    if (bytes[0] === 0xff && bytes[1] === 0xd8) {
      profile = jpegProfileBytes(bytes);
    } else if (bytes[0] === 0x89 && ascii(bytes, 1, 3) === "PNG") {
      profile = await pngProfileBytes(bytes);
    } else if (ascii(bytes, 0, 4) === "RIFF" && ascii(bytes, 8, 4) === "WEBP") {
      profile = webpProfileBytes(bytes);
    }
    return parseIccProfile(profile);
  } catch {
    return null;
  }
}

// True for no profile, a grayscale profile, or sRGB / Adobe RGB / Display P3.
export function profileIsAccepted(profile) {
  if (!profile?.name || profile.space === "GRAY") {
    return true;
  }
  return ACCEPTED.test(profile.name);
}

// The name of the profile that makes this File unacceptable, or null.
export async function unsupportedColourProfile(file) {
  try {
    if (!file) {
      return null;
    }
    const buffer = await file.slice(0, HEAD_BYTES).arrayBuffer();
    const profile = await readEmbeddedProfile(buffer);
    return profileIsAccepted(profile) ? null : profile.name;
  } catch {
    return null;
  }
}

// Call before uploading a File. When its colour profile is not accepted,
// tells the member why and returns true: the caller must not upload it.
export async function refuseUnsupportedColourProfile(
  file,
  { dialog, siteSettings }
) {
  if (!siteSettings.npn_submissions_block_unsupported_colour_profiles) {
    return false;
  }
  const profile = await unsupportedColourProfile(file);
  if (!profile) {
    return false;
  }
  dialog.alert(
    i18n("npn_submissions.form.images.colour_profile_blocked", { profile })
  );
  return true;
}
