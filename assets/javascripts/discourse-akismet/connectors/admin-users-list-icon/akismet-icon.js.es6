export default {
  shouldRender(args) {
    return args.query === "suspect";
  },

  setupComponent(args, component) {
    switch (args.user.akismet_state) {
      case "pending":
        component.set("icon", "far-clock");
        break;
      case "skipped":
        component.set("icon", "question");
        break;
      case "confirmed_ham":
        component.set("icon", "check");
        break;
      case "confirmed_spam":
        component.set("icon", "times");
        break;
    }
  },
};
