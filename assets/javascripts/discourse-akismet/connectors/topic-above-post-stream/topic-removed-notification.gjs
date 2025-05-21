import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { service } from "@ember/service";
import helperFn from "discourse/helpers/helper-fn";
import { i18n } from "discourse-i18n";

const DELETED_CHANNEL_PREFIX = "/discourse-akismet/topic-deleted/";

export default class TopicRemovedNotification extends Component {
  @service messageBus;

  @tracked akismetFlaggedTopic;

  subscribeMessageBus = helperFn(({ topicId }, on) => {
    this.akismetFlaggedTopic = false;

    const channel = `${DELETED_CHANNEL_PREFIX}${topicId}`;

    const cb = () => (this.akismetFlaggedTopic = true);
    this.messageBus.subscribe(channel, cb);

    on.cleanup(() => this.messageBus.unsubscribe(channel, cb));
  });

  <template>
    {{this.subscribeMessageBus topicId=@outletArgs.model.id}}
    {{#if this.akismetFlaggedTopic}}
      <div class="alert alert-info category-read-only-banner">
        {{i18n "akismet.topic_deleted"}}
      </div>
    {{/if}}
  </template>
}
