import { apiInitializer } from "discourse/lib/api";
import NpnEditWithFormButton from "../components/npn-edit-with-form-button";

// "Edit with form" next to the normal edit button on the first post of a
// submission topic the viewer may edit. The component's shouldRender repeats
// the check so the button hides if `can_edit` changes later.
export default apiInitializer((api) => {
  api.registerValueTransformer(
    "post-menu-buttons",
    ({ value: dag, context: { post, buttonKeys } }) => {
      if (post?.post_number !== 1 || !post?.topic?.npn_edit_submission_id) {
        return;
      }
      dag.add("npn-edit-with-form", NpnEditWithFormButton, {
        before: buttonKeys.EDIT,
      });
    }
  );
});
