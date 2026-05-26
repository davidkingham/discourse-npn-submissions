import { service } from "@ember/service";
import DiscourseRoute from "discourse/routes/discourse";

const VALID_TYPES = ["image", "project", "weekly_challenge"];

export default class SubmitRoute extends DiscourseRoute {
  @service currentUser;

  queryParams = {
    type: { refreshModel: true },
  };

  model(params) {
    const requested = params.type;
    const valid = VALID_TYPES.includes(requested);
    return {
      requestedType: requested ?? null,
      resolvedType: valid ? requested : null,
      invalid: requested != null && !valid,
      signedIn: !!this.currentUser,
      canSubmit: !!this.currentUser?.can_npn_submit,
    };
  }
}
