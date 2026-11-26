// Reads the name of the ICC colour profile embedded in a photo, in the
// browser, so the form can tell the photographer when their file is in a
// profile that will not look the same everywhere on NPN.
//
// ORIGINAL CODE written for this plugin (MIT, same as the plugin). It follows
// the public JPEG (APP2 "ICC_PROFILE"), PNG (iCCP), WebP (ICCP) and ICC.1
// profile layouts. No third-party source was copied or vendored.
//
// Why only some profiles warn: an 8-bit ProPhoto RGB JPEG is drawn 1 to 2
// dE2000 redder by browsers than by Photoshop (see the comment on
// DiscourseNpnSubmissions::SrgbUploadExtension, which converts those files
// on upload), and monitor / unknown profiles are export mistakes. sRGB,
// Adobe RGB and Display P3 display consistently and are left alone.
//
// Fully defensive: missing, truncated or malformed input reads as "no
// profile", and nothing here throws — it can never block an upload.

// Keep in step with LEFT_ALONE in lib/extensions/srgb_upload_extension.rb.
const LEFT_ALONE = /srgb|^c2$|adobe\s*rgb|display\s*p3|apple wide color/i;

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

async function inflate(bytes) {
  if (typeof DecompressionStream === "undefined") {
    return null;
  }
  const stream = new Blob([bytes])
    .stream()
    .pipeThrough(new DecompressionStream("deflate"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
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

// True when a profile is one the photographer should hear about: anything
// that isn't sRGB, Adobe RGB or Display P3. Grayscale profiles never warn.
export function profileNeedsWarning(profile) {
  if (!profile?.name || profile.space === "GRAY") {
    return false;
  }
  return !LEFT_ALONE.test(profile.name);
}

// Keyed by the /uploads.json response object, so nothing is added to the
// upload itself (it is saved into drafts and submissions) and entries vanish
// with the upload. Restored drafts have no entry and so show no warning.
const WARNINGS = new WeakMap();

// Call with the original File and the upload it produced, before the upload
// is put on screen. Never throws.
export async function noteColourProfile(file, upload) {
  try {
    if (!file || !upload || typeof upload !== "object") {
      return;
    }
    const buffer = await file.slice(0, HEAD_BYTES).arrayBuffer();
    const profile = await readEmbeddedProfile(buffer);
    if (profileNeedsWarning(profile)) {
      WARNINGS.set(upload, profile.name);
    }
  } catch {
    // Reading the profile is a courtesy; an upload must never fail over it.
  }
}

// The profile name to warn about for this upload, or null.
export function colourProfileWarningFor(upload) {
  return (upload && WARNINGS.get(upload)) || null;
}
