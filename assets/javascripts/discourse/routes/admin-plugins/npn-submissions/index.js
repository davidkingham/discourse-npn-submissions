import DiscourseRoute from "discourse/routes/discourse";

export default class AdminNpnSubmissionsIndexRoute extends DiscourseRoute {
  model() {
    return this.modelFor("adminPlugins.npn-submissions");
  }
}
