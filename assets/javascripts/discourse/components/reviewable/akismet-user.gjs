import Component from "@ember/component";
import { registerReviewableTypeLabel } from "discourse/components/reviewable/item";
import User from "discourse/components/reviewable/user";

registerReviewableTypeLabel("ReviewableAkismetUser", "review.user_label");

export default class ReviewableUser extends Component {
  <template>
    <div class="review-item__meta-content">
      <User @reviewable={{@reviewable}}>
        {{yield}}
      </User>
    </div>
  </template>
}
