import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { inject as service } from "@ember/service";

export default class ReviewableAkismetPostVotingComment extends Component {
  @service store;
  @tracked post;

  constructor() {
    super(...arguments);
    this.fetchPost();
  }
  async fetchPost() {
    this.post = await this.store.find("post", this.args.reviewable.post_id);
  }
}
