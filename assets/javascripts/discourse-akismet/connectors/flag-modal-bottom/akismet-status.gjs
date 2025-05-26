import Component from "@ember/component";
import { concat } from "@ember/helper";
import { classNames, tagName } from "@ember-decorators/component";
import { i18n } from "discourse-i18n";

@tagName("div")
@classNames("flag-modal-bottom-outlet", "akismet-status")
export default class AkismetStatus extends Component {
  <template>
    {{#if this.post.akismet_state}}
      <div class="consent_banner alert alert-info">
        <span>{{i18n
            (concat "akismet.post_state." this.post.akismet_state)
          }}</span>
      </div>
    {{/if}}
  </template>
}
