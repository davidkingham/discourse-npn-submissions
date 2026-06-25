// Resolve the real focus target for a form field matched by CSS selector.
//
// A plain <input>/<textarea> is focused directly. NpnField now renders a rich
// DEditor whose underlying <textarea> (the element carrying the field id) is
// hidden in WYSIWYG mode, so focusing it would put focus on a non-visible node.
// When the matched element lives inside a `.d-editor`, focus the visible
// ProseMirror surface (`.d-editor-input`) instead.
export function resolveFieldFocusTarget(el) {
  if (!el) {
    return null;
  }
  return el.closest(".d-editor")?.querySelector(".d-editor-input") || el;
}

// Convenience: query by selector and focus the resolved target without
// scrolling the viewport (callers manage scroll separately).
export function focusFieldBySelector(selector) {
  const target = resolveFieldFocusTarget(document.querySelector(selector));
  target?.focus({ preventScroll: true });
  return target;
}
