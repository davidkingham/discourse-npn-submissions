import { withPluginApi } from "discourse/lib/plugin-api";

const PLUGIN_ID = "discourse-npn-submissions";

export default {
  name: "npn-submissions-admin-plugin-configuration-nav",

  initialize(container) {
    const currentUser = container.lookup("service:current-user");
    if (!currentUser?.admin) {
      return;
    }

    withPluginApi((api) => {
      api.setAdminPluginIcon(PLUGIN_ID, "camera");
    });
  },
};
