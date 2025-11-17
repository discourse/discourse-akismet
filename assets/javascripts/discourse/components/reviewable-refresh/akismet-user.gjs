import Component from "@ember/component";
import { registerReviewableTypeLabel } from "discourse/components/reviewable-refresh/item";
import LegacyReviewableUser from "discourse/components/reviewable-user";

registerReviewableTypeLabel("ReviewableAkismetUser", "review.user_label");

export default class ReviewableUser extends Component {
  <template>
    <div class="review-item__meta-content">
      <LegacyReviewableUser @reviewable={{@reviewable}}>
        {{yield}}
      </LegacyReviewableUser>
    </div>
  </template>
}
