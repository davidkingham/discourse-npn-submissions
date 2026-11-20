import Controller from "@ember/controller";

export default class SubmitController extends Controller {
  queryParams = ["type", "edit", "form", "draft"];
  edit = null;
  form = null;
  draft = null;
}
