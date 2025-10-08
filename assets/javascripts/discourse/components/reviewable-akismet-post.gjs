import Component from "@ember/component";
import { htmlSafe } from "@ember/template";
import ReviewableCreatedBy from "discourse/components/reviewable-created-by";
import ReviewableCreatedByName from "discourse/components/reviewable-created-by-name";
import ReviewableTopicLink from "discourse/components/reviewable-topic-link";
import ReviewableAkismetApiError from "./reviewable-akismet-api-error";

export default class extends Component {
  <template>
    <ReviewableTopicLink @reviewable={{this.reviewable}} @tagName="" />

    <div class="post-contents-wrapper">
      <ReviewableCreatedBy
        @user={{this.reviewable.target_created_by}}
        @tagName=""
      />

      <div class="post-contents">
        <ReviewableCreatedByName
          @user={{this.reviewable.target_created_by}}
          @tagName=""
        />

        <div class="post-body">
          {{htmlSafe this.reviewable.payload.post_cooked}}
        </div>

        {{yield}}

        {{#if this.reviewable.payload.external_error}}
          <ReviewableAkismetApiError
            @external_error={{this.reviewable.payload.external_error}}
          />
        {{/if}}
      </div>
    </div>
  </template>
}
