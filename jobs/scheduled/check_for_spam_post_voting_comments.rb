# frozen_string_literal: true

module Jobs
  class CheckForSpamPostsVotingComments < ::Jobs::Scheduled
    every SiteSetting.spam_check_interval_mins.minutes

    def execute(args)
      return unless SiteSetting.akismet_enabled?
      return unless defined?(SiteSetting.post_voting_enabled) && SiteSetting.post_voting_enabled?
      return if DiscourseAkismet::AntiSpamService.api_secret_blank?

      bouncer = DiscourseAkismet::PostVotingCommentsBouncer.new
      client = DiscourseAkismet::AntiSpamService.client
      spam_count = 0

      DiscourseAkismet::PostVotingCommentsBouncer
        .to_check
        .where(deleted_at: nil)
        .find_each do |comment|
          DistributedMutex.synchronize("akismet_post_voting_comment_#{comment.id}") do
            if comment.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE] ==
                 DiscourseAkismet::Bouncer::PENDING_STATE
              spam_count += 1 if bouncer.perform_check(client, comment)
            end
          end
        end

      # Trigger an event that akismet found spam. This allows people to
      # notify chat rooms or whatnot
      DiscourseEvent.trigger(:akismet_found_spam, spam_count) if spam_count > 0
    end
  end
end
