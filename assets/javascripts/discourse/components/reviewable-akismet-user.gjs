import Component from "@ember/component";
import { concat } from "@ember/helper";
import ReviewableField from "discourse/components/reviewable-field";
import getUrl from "discourse/helpers/get-url";
import { i18n } from "discourse-i18n";
import ReviewableAkismetApiError from "./reviewable-akismet-api-error";

export default class extends Component {
  <template>
    <div class="reviewable-user-info">
      <div class="reviewable-user-fields">
        <div class="reviewable-user-details username">
          <div class="name">{{i18n "review.user.username"}}</div>
          <div class="value">
            {{#if this.reviewable.user_deleted}}
              {{this.reviewable.payload.username}}
            {{else}}
              <a
                href={{getUrl
                  (concat "/u/" this.reviewable.payload.username "/summary")
                }}
              >
                {{this.reviewable.payload.username}}
              </a>
            {{/if}}
          </div>
        </div>

        <ReviewableField
          @classes="reviewable-user-details name"
          @name={{i18n "review.user.name"}}
          @value={{this.reviewable.payload.name}}
        />

        <ReviewableField
          @classes="reviewable-user-details email"
          @name={{i18n "review.user.email"}}
          @value={{this.reviewable.payload.email}}
        />

        <ReviewableField
          @classes="reviewable-user-details bio"
          @name={{i18n "review.user.bio"}}
          @value={{this.reviewable.payload.bio}}
        />
      </div>

      {{yield}}

      {{#if this.reviewable.payload.external_error}}
        <ReviewableAkismetApiError
          @external_error={{this.reviewable.payload.external_error}}
        />
      {{/if}}
    </div>
  </template>
}
