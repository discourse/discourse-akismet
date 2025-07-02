import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "add-akismet-state",

  initialize() {
    withPluginApi((api) => {
      api.addTrackedPostProperties("akismet_state");
    });
  },
};
