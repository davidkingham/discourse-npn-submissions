// Which image form /submit opens: the classic one or the photo-first one.
// Kept free of components so the rule is unit-tested.

const STORAGE_KEY = "npn_submissions_image_form";
const FORMS = ["new", "classic"];

// The address wins (?form=new / ?form=classic), then what this member last
// switched to, then the site's default. Always classic while the photo-first
// form is switched off.
export function chooseImageForm({ enabled, param, remembered, defaultNew }) {
  if (!enabled) {
    return "classic";
  }
  if (FORMS.includes(param)) {
    return param;
  }
  if (FORMS.includes(remembered)) {
    return remembered;
  }
  return defaultNew ? "new" : "classic";
}

// The choice is kept in this browser only. Storage can be unavailable (private
// windows, blocked site data), in which case the site default simply applies.
export function rememberedImageForm() {
  try {
    return window.localStorage.getItem(STORAGE_KEY);
  } catch {
    return null;
  }
}

export function rememberImageForm(form) {
  try {
    window.localStorage.setItem(STORAGE_KEY, form);
  } catch {
    // Nothing to do: the member just gets the site default next time.
  }
}
