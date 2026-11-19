import Component from "@glimmer/component";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/ui-kit/d-button";

// Post-menu button on the first post of a topic created through the
// submission form: reopens the post in that form (/submit?edit=<id>) so the
// photographer can revise text, tags and (before anyone replies) images in
// the familiar interface. The topic view only exposes
// `npn_edit_submission_id` when the viewer may edit the post; the edit
// endpoints check again.
export default class NpnEditWithFormButton extends Component {
  static shouldRender(args) {
    const post = args?.post;
    return (
      post?.post_number === 1 &&
      !!post?.can_edit &&
      !!post?.topic?.npn_edit_submission_id
    );
  }

  @service router;

  @action
  openForm() {
    this.router.transitionTo("submit", {
      queryParams: {
        edit: this.args.post.topic.npn_edit_submission_id,
        type: null,
      },
    });
  }

  <template>
    <DButton
      class="post-action-menu__npn-edit-with-form"
      ...attributes
      @action={{this.openForm}}
      @icon="rectangle-list"
      @label="npn_submissions.edit_with_form.button"
      @title="npn_submissions.edit_with_form.title"
    />
  </template>
}
