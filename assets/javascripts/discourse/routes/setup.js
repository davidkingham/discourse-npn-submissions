import { service } from "@ember/service";
import User from "discourse/models/user";
import DiscourseRoute from "discourse/routes/discourse";

// Profile setup page. Unlike /submit this is NOT a submission flow and is open
// to any signed-in user (not gated behind `can_npn_submit`). It loads the
// current user's full details so the form can prefill existing values and
// behave as an "edit my profile" page rather than a blank wizard.
export default class SetupRoute extends DiscourseRoute {
  @service currentUser;

  async model() {
    if (!this.currentUser) {
      return { signedIn: false, user: null };
    }
    const user = await User.findByUsername(this.currentUser.username);
    return { signedIn: true, user };
  }
}
