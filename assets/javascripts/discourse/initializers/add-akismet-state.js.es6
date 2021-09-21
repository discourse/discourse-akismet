import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "add-akismet-state",

  initialize() {
    withPluginApi("0.8.31", (api) => {
      api.includePostAttributes("akismet_state");
    });
  },
};
