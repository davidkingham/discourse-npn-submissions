import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { extractError } from "discourse/lib/ajax-error";
import DiscourseRoute from "discourse/routes/discourse";

const VALID_TYPES = [
  "image",
  "project",
  "weekly_challenge",
  "introduction",
  "new_member_image",
  "help",
];

export default class SubmitRoute extends DiscourseRoute {
  @service currentUser;
  @service siteSettings;

  queryParams = {
    type: { refreshModel: true },
    edit: { refreshModel: true },
    form: { refreshModel: true },
    draft: { refreshModel: true },
  };

  async model(params) {
    const base = {
      signedIn: !!this.currentUser,
      canSubmit: !!this.currentUser?.can_npn_submit,
    };

    // /submit?edit=<submission id>: reopen a published post in its form. The
    // submission's own type picks the form; `type` is ignored.
    if (params.edit) {
      if (!this.currentUser) {
        return { ...base, resolvedType: null, invalid: false };
      }
      try {
        const editState = await ajax(
          `/npn-submissions/submissions/${encodeURIComponent(params.edit)}/edit`
        );
        const type = editState.submission?.submission_type;
        return {
          ...base,
          // Editing your own post doesn't need the submit permission; the
          // server already checked ownership and Discourse's edit rules.
          canSubmit: true,
          requestedType: type,
          resolvedType: VALID_TYPES.includes(type) ? type : null,
          invalid: !VALID_TYPES.includes(type),
          editState,
        };
      } catch (e) {
        return {
          ...base,
          canSubmit: true,
          resolvedType: null,
          invalid: false,
          editError: extractError(e),
        };
      }
    }

    const requested = params.type;
    const valid = VALID_TYPES.includes(requested);
    return {
      ...base,
      requestedType: requested ?? null,
      resolvedType: valid ? requested : null,
      invalid: requested != null && !valid,
      // ?form=new opts into the photo-first image form while it is on test;
      // ?draft=<id> reopens a draft (used when switching between the forms).
      useNewForm:
        params.form === "new" &&
        !!this.siteSettings.npn_submissions_new_image_form_enabled,
      resumeDraftId: params.draft ?? null,
    };
  }
}
