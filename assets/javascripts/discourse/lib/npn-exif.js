// Minimal, dependency-free EXIF reader for JPEG files, used to optionally
// pre-fill Technical Details from a photo's capture settings.
//
// ORIGINAL CODE written for this plugin (MIT, same as the plugin). It implements
// the public JPEG (JFIF) + EXIF/TIFF binary layout described in the EXIF 2.3 /
// TIFF 6.0 specifications. No third-party source was copied or vendored.
//
// Scope and safety:
//   - Reads only a small set of SAFE tags: Make, Model, LensModel, FocalLength,
//     ExposureTime, FNumber, ISO, Flash. It deliberately never touches the GPS
//     IFD, serial numbers, or any timestamp.
//   - Works on an ArrayBuffer in the browser; the caller passes a small slice of
//     the original file (EXIF lives near the start).
//   - Fully defensive: malformed / stripped / non-JPEG input returns null, and
//     it never throws — so it can never block upload, draft, preview, or submit.

// Byte size of each TIFF field type (only the ones we read are meaningful).
const TYPE_SIZES = { 1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 7: 1, 9: 4, 10: 8 };

// EXIF tag ids we care about — all "safe" (no GPS, serials, or dates).
const TAG = {
  MAKE: 0x010f,
  MODEL: 0x0110,
  EXIF_IFD: 0x8769,
  EXPOSURE_TIME: 0x829a,
  F_NUMBER: 0x829d,
  ISO: 0x8827,
  FOCAL_LENGTH: 0x920a,
  FLASH: 0x9209,
  LENS_MODEL: 0xa434,
};

function readValue(view, tiffStart, type, count, valueFieldOffset, le) {
  const size = TYPE_SIZES[type];
  if (!size) {
    return null;
  }
  const total = size * count;
  // Values up to 4 bytes are stored inline; larger ones are at an offset.
  const dataOffset =
    total <= 4
      ? valueFieldOffset
      : tiffStart + view.getUint32(valueFieldOffset, le);
  if (dataOffset < 0 || dataOffset + total > view.byteLength) {
    return null;
  }

  switch (type) {
    case 2: {
      // ASCII string
      let s = "";
      for (let i = 0; i < count; i++) {
        const c = view.getUint8(dataOffset + i);
        if (c === 0) {
          break;
        }
        s += String.fromCharCode(c);
      }
      return { ascii: s.trim() };
    }
    case 3:
      return { int: view.getUint16(dataOffset, le) };
    case 4:
      return { int: view.getUint32(dataOffset, le) };
    case 5:
      return {
        rational: {
          num: view.getUint32(dataOffset, le),
          den: view.getUint32(dataOffset + 4, le),
        },
      };
    default:
      return null;
  }
}

function readIfd(view, tiffStart, ifdOffset, le) {
  const tags = {};
  if (ifdOffset < 0 || ifdOffset + 2 > view.byteLength) {
    return tags;
  }
  const count = view.getUint16(ifdOffset, le);
  if (count > 512) {
    return tags; // sanity cap against malformed data
  }
  for (let i = 0; i < count; i++) {
    const entry = ifdOffset + 2 + i * 12;
    if (entry + 12 > view.byteLength) {
      break;
    }
    const tag = view.getUint16(entry, le);
    const type = view.getUint16(entry + 2, le);
    const valueCount = view.getUint32(entry + 4, le);
    tags[tag] = readValue(view, tiffStart, type, valueCount, entry + 8, le);
  }
  return tags;
}

// Parse the raw safe EXIF values from a JPEG ArrayBuffer. Returns null when the
// buffer is not a JPEG or has no readable EXIF.
export function readJpegExif(buffer) {
  try {
    const view = new DataView(buffer);
    if (view.byteLength < 4 || view.getUint16(0) !== 0xffd8) {
      return null; // no JPEG SOI marker
    }

    // Walk the segment markers to find the APP1 "Exif" segment.
    let offset = 2;
    let tiffStart = -1;
    for (let guard = 0; guard < 32 && offset + 4 <= view.byteLength; guard++) {
      const marker = view.getUint16(offset);
      // Bitwise AND is intentional here — JPEG marker validation tests that the
      // high byte is 0xFF, the protocol-defined marker prefix.
      // eslint-disable-next-line no-bitwise
      if ((marker & 0xff00) !== 0xff00) {
        break; // not a marker boundary
      }
      if (marker === 0xffda) {
        break; // start of scan — metadata segments are done
      }
      const size = view.getUint16(offset + 2);
      if (size < 2) {
        break;
      }
      if (marker === 0xffe1) {
        const sig = offset + 4;
        if (
          sig + 6 <= view.byteLength &&
          view.getUint32(sig) === 0x45786966 && // "Exif"
          view.getUint16(sig + 4) === 0x0000
        ) {
          tiffStart = sig + 6;
          break;
        }
      }
      offset += 2 + size;
    }
    if (tiffStart < 0 || tiffStart + 8 > view.byteLength) {
      return null;
    }

    // TIFF header: byte order, magic number, then the IFD0 offset.
    const bom = view.getUint16(tiffStart);
    const le = bom === 0x4949 ? true : bom === 0x4d4d ? false : null;
    if (le === null || view.getUint16(tiffStart + 2, le) !== 0x002a) {
      return null;
    }
    const ifd0 = readIfd(
      view,
      tiffStart,
      tiffStart + view.getUint32(tiffStart + 4, le),
      le
    );

    const out = {
      make: ifd0[TAG.MAKE]?.ascii || null,
      model: ifd0[TAG.MODEL]?.ascii || null,
    };

    const exifPtr = ifd0[TAG.EXIF_IFD]?.int;
    if (exifPtr) {
      const exif = readIfd(view, tiffStart, tiffStart + exifPtr, le);
      out.lensModel = exif[TAG.LENS_MODEL]?.ascii || null;
      out.focalLength = exif[TAG.FOCAL_LENGTH]?.rational || null;
      out.exposureTime = exif[TAG.EXPOSURE_TIME]?.rational || null;
      out.fNumber = exif[TAG.F_NUMBER]?.rational || null;
      out.iso = exif[TAG.ISO]?.int || null;
      // Flash is a bitmask where 0 (did not fire) is meaningful, so keep 0
      // rather than collapsing it to null like the fields above.
      out.flash = exif[TAG.FLASH]?.int ?? null;
    }
    return out;
  } catch {
    return null;
  }
}

function ratio(r) {
  if (!r || !r.den) {
    return null;
  }
  const v = r.num / r.den;
  return isFinite(v) && v > 0 ? v : null;
}

function pretty(v) {
  return Number.isInteger(v) ? String(v) : v.toFixed(1);
}

function formatCamera(make, model) {
  const m = (model || "").trim();
  const mk = (make || "").trim();
  if (!m) {
    return mk || null;
  }
  if (!mk) {
    return m;
  }
  // Avoid "NIKON NIKON Z 8" when the model already includes the brand.
  const brand = mk.split(/\s+/)[0].toLowerCase();
  return m.toLowerCase().startsWith(brand) ? m : `${mk} ${m}`;
}

function formatShutter(r) {
  const v = ratio(r);
  if (v === null) {
    return null;
  }
  if (v >= 1) {
    return `${pretty(v)}s`;
  }
  const denom = Math.round(r.den / r.num);
  return denom > 0 ? `1/${denom}s` : null;
}

// Decode the EXIF Flash bitmask. We only ever report when the flash actually
// fired; bit 0 (fired) is the reliable bit across manufacturers. A flash that
// did not fire — or a camera with no flash function — produces no line.
function formatFlash(v) {
  if (v === null || v === undefined) {
    return null;
  }
  // Bitwise test against the EXIF-defined Flash bitmask; bit 0 means fired.
  // eslint-disable-next-line no-bitwise
  return v & 0x01 ? "Fired" : null;
}

// Build the labeled, multi-line string from raw EXIF, omitting missing fields.
// Returns null when nothing useful was found.
export function formatPhotoMetadata(exif) {
  if (!exif) {
    return null;
  }
  const lines = [];
  const camera = formatCamera(exif.make, exif.model);
  if (camera) {
    lines.push(`Camera: ${camera}`);
  }
  if (exif.lensModel) {
    lines.push(`Lens: ${exif.lensModel}`);
  }
  const focal = ratio(exif.focalLength);
  if (focal) {
    lines.push(`Focal length: ${Math.round(focal)}mm`);
  }
  const shutter = formatShutter(exif.exposureTime);
  if (shutter) {
    lines.push(`Shutter speed: ${shutter}`);
  }
  const aperture = ratio(exif.fNumber);
  if (aperture) {
    lines.push(`Aperture: f/${pretty(aperture)}`);
  }
  if (exif.iso) {
    lines.push(`ISO: ${exif.iso}`);
  }
  const flash = formatFlash(exif.flash);
  if (flash) {
    lines.push(`Flash: ${flash}`);
  }
  return lines.length ? lines.join("\n") : null;
}

// Public entry point: given a browser File, return the formatted metadata string
// or null. JPEG only; never throws.
export async function extractPhotoMetadata(file) {
  try {
    if (!file) {
      return null;
    }
    const name = (file.name || "").toLowerCase();
    const type = (file.type || "").toLowerCase();
    const isJpeg = type === "image/jpeg" || /\.jpe?g$/.test(name);
    if (!isJpeg) {
      return null;
    }
    // EXIF lives near the start; read a generous slice rather than the whole file.
    const slice = file.slice(0, 512 * 1024);
    const buffer = await slice.arrayBuffer();
    return formatPhotoMetadata(readJpegExif(buffer));
  } catch {
    return null;
  }
}
