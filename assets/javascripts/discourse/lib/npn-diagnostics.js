// Client-side diagnostic info for the Help form. Reads browser, OS,
// device/viewport, and same-origin came-from URL, formats them as a small
// Markdown bullet list that the server simply wraps in [details]. The user
// sees the formatted preview before submit; an opt-out checkbox suppresses
// the field entirely.
//
// Privacy posture:
//   - All values are collected client-side at form interaction time.
//   - Only same-origin document.referrer is included — external referrers
//     are dropped, both to avoid leaking unrelated tabs into the post and
//     because off-site context is rarely useful for moderators.
//   - Nothing leaves the browser unless the user submits the form with the
//     diagnostic toggle on. The plugin never collects any of this server-
//     side independently.

// Parse a UA string into a friendly "Brand Version" pair for the common
// browsers. UA-CH (navigator.userAgentData) is preferred when available;
// regex fallback otherwise. Always returns *something* readable.
export function detectBrowser() {
  const uaData = navigator.userAgentData;
  if (uaData?.brands?.length) {
    // Pick the most-specific brand: skip placeholders ("Not.A/Brand",
    // "Not A;Brand") and the generic "Chromium" entry that ships with
    // every Chromium-based browser.
    const primary =
      uaData.brands.find(
        (b) => !/Not[.\s_/-]?A[.\s_/-]?Brand|Chromium/i.test(b.brand)
      ) || uaData.brands[0];
    if (primary) {
      return `${primary.brand} ${primary.version}`;
    }
  }

  const ua = navigator.userAgent || "";
  // Order matters: Edge UA contains both "Chrome" and "Edg/" so Edge must
  // be checked first; Safari UA contains "Safari" and "Version" but not
  // "Chrome".
  if (/Firefox\/(\d+)/.test(ua)) {
    return `Firefox ${RegExp.$1}`;
  }
  if (/Edg\/(\d+)/.test(ua)) {
    return `Edge ${RegExp.$1}`;
  }
  if (/OPR\/(\d+)/.test(ua)) {
    return `Opera ${RegExp.$1}`;
  }
  if (/Chrome\/(\d+)/.test(ua) && !/Edg\//.test(ua)) {
    return `Chrome ${RegExp.$1}`;
  }
  if (/Version\/(\d+).*Safari/.test(ua) && !/Chrome/.test(ua)) {
    return `Safari ${RegExp.$1}`;
  }
  return "Unknown browser";
}

export function detectOS() {
  const uaData = navigator.userAgentData;
  if (uaData?.platform) {
    return uaData.platform; // e.g. "macOS", "Windows", "Android"
  }

  const ua = navigator.userAgent || "";
  if (/Windows NT (\d+\.\d+)/.test(ua)) {
    return `Windows ${RegExp.$1}`;
  }
  if (/Mac OS X (\d+[._]\d+)/.test(ua)) {
    return `macOS ${RegExp.$1.replace("_", ".")}`;
  }
  if (/Android (\d+)/.test(ua)) {
    return `Android ${RegExp.$1}`;
  }
  if (/iPhone OS (\d+_\d+)/.test(ua)) {
    return `iOS ${RegExp.$1.replace("_", ".")}`;
  }
  if (/iPad.*OS (\d+_\d+)/.test(ua)) {
    return `iPadOS ${RegExp.$1.replace("_", ".")}`;
  }
  if (/Linux/.test(ua)) {
    return "Linux";
  }
  return "Unknown OS";
}

// "Desktop" / "Mobile" / "Tablet" plus the viewport size. Uses the UA-CH
// `mobile` flag when present; falls back to viewport width.
export function detectDeviceAndViewport() {
  const width = window.innerWidth || 0;
  const height = window.innerHeight || 0;
  const uaData = navigator.userAgentData;

  let kind = "Desktop";
  if (uaData) {
    kind = uaData.mobile ? "Mobile" : "Desktop";
  } else if (width > 0) {
    // Rough breakpoints — moderators just need a hint, not certainty.
    if (width < 600) {
      kind = "Mobile";
    } else if (width < 1024) {
      kind = "Tablet";
    }
  }

  const viewport = width && height ? `${width}×${height}` : null;
  return viewport ? `${kind} (${viewport})` : kind;
}

// Same-origin referrer only. Returns null when there's no referrer or when
// it points to a different origin.
export function detectReferrer() {
  const raw = document.referrer || "";
  if (!raw) {
    return null;
  }
  try {
    const ref = new URL(raw);
    if (ref.origin !== window.location.origin) {
      return null;
    }
    return ref.toString();
  } catch {
    return null;
  }
}

// Collect everything into a plain object — useful for the form's preview
// rendering.
export function collectDiagnostics() {
  return {
    browser: detectBrowser(),
    os: detectOS(),
    device: detectDeviceAndViewport(),
    referrer: detectReferrer(),
  };
}

// Format a diagnostics object as the Markdown bullet list that the server's
// HelpPostBuilder wraps in [details]. Returns an empty string when the
// object is blank, so the post builder naturally omits the block.
export function formatDiagnostics(diag, labels) {
  if (!diag) {
    return "";
  }
  const rows = [];
  if (diag.browser) {
    rows.push(`- **${labels.browser}:** ${diag.browser}`);
  }
  if (diag.os) {
    rows.push(`- **${labels.os}:** ${diag.os}`);
  }
  if (diag.device) {
    rows.push(`- **${labels.device}:** ${diag.device}`);
  }
  if (diag.referrer) {
    rows.push(`- **${labels.referrer}:** ${diag.referrer}`);
  }
  return rows.join("\n");
}
