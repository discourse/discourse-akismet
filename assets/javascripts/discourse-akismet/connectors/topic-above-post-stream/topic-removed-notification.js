const DELETED_CHANNEL_PREFIX = "/discourse-akismet/topic-deleted/";

export default {
  setupComponent(args, component) {
    component.messageBus.subscribe(
      `${DELETED_CHANNEL_PREFIX}${args.model.id}`,
      () => {
        component.set("akismetFlaggedTopic", true);
      }
    );
  },

  teardownComponent(component) {
    component.messageBus.unsubscribe(
      `${DELETED_CHANNEL_PREFIX}${component.model.id}`
    );
  },
};
