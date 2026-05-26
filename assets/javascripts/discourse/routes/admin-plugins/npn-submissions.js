import { ajax } from "discourse/lib/ajax";
import DiscourseRoute from "discourse/routes/discourse";

export default class AdminNpnSubmissionsRoute extends DiscourseRoute {
  model() {
    return ajax("/admin/npn-submissions.json");
  }
}
