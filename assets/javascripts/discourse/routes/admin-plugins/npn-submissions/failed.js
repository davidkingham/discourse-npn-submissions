import { ajax } from "discourse/lib/ajax";
import DiscourseRoute from "discourse/routes/discourse";

export default class AdminNpnSubmissionsFailedRoute extends DiscourseRoute {
  model() {
    return ajax("/admin/npn-submissions/failed.json");
  }
}
