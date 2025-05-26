import Component from "@ember/component";
import { i18n } from "discourse-i18n";

export default class extends Component {
  <template>
    <div class="reviewable-score-reason">
      {{i18n "admin.akismet_api_error"}}
      {{this.external_error.error}}
      ({{this.external_error.code}})
      {{this.external_error.msg}}
    </div>
  </template>
}
