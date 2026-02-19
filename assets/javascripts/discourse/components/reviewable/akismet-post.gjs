import ReviewablePost from "discourse/components/reviewable/post";
import { i18n } from "discourse-i18n";
import ReviewableAkismetApiError from "../reviewable-akismet-api-error";

<template>
  <ReviewablePost
    @reviewable={{@reviewable}}
    @userLabel={{i18n "review.flagged_user"}}
    @pluginOutletName="after-reviewable-akismet-post-body"
  >
    {{#if @reviewable.payload.external_error}}
      <ReviewableAkismetApiError
        @external_error={{@reviewable.payload.external_error}}
      />
    {{/if}}
  </ReviewablePost>
</template>
