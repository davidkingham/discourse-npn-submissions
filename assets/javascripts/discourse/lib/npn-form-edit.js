import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";

// Shared edit-with-form plumbing for the submission forms. A form opened from
// /submit?edit=<id> gets `@editState` from the route:
//   { submission, images_locked, edited_outside_form }
// and saves back over the published post instead of creating a topic.
//
// Each form declares the tracked `editing`, `imagesLocked` and
// `editedOutsideForm` properties itself (so templates re-render), calls
// `startEditing` from its constructor, and routes Submit through `saveEdit`.

// Puts `form` into edit mode. Returns true when `editState` is present.
export function startEditing(form, editState) {
  if (!editState?.submission) {
    return false;
  }
  form.editing = true;
  form.editSubmissionId = editState.submission.id;
  form.editTopicUrl = editState.submission.topic_url;
  form.imagesLocked = !!editState.images_locked;
  form.editedOutsideForm = !!editState.edited_outside_form;
  // Edits go straight to the post on Save; never into a draft row.
  form.autosaver?.stop();
  return true;
}

// PUT the form back over the post and return to the topic. The server answers
// 409 when the post was changed outside the form; ask, then retry with
// `force`. `form` needs buildPayload(), router, dialog, editSubmissionId and
// editTopicUrl.
export async function saveEdit(form, force = false) {
  const payload = form.buildPayload();
  if (force) {
    payload.force = true;
  }
  try {
    const result = await ajax(
      `/npn-submissions/submissions/${form.editSubmissionId}`,
      {
        type: "PUT",
        contentType: "application/json",
        data: JSON.stringify(payload),
      }
    );
    form.router.transitionTo(result.submission?.topic_url || form.editTopicUrl);
    return true;
  } catch (e) {
    if (e.jqXHR?.status === 409 && e.jqXHR?.responseJSON?.edited_outside_form) {
      form.dialog.confirm({
        message: i18n("npn_submissions.form.edit.overwrite_confirm"),
        confirmButtonLabel: "npn_submissions.form.edit.overwrite_button",
        didConfirm: () => form.submitEdit(true),
      });
    } else {
      popupAjaxError(e);
    }
    return false;
  }
}
