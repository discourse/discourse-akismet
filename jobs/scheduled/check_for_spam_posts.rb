# frozen_string_literal: true

module Jobs
  class CheckForSpamPosts < ::Jobs::Scheduled
    every SiteSetting.spam_check_interval_mins.minutes

    def execute(args)
      return unless SiteSetting.akismet_enabled?
      return if DiscourseAkismet::AntiSpamService.api_secret_blank?

      bouncer = DiscourseAkismet::PostsBouncer.new
      client = DiscourseAkismet::AntiSpamService.client
      spam_count = 0

      DiscourseAkismet::PostsBouncer
        .to_check
        .where(user_deleted: false)
        .find_each do |post|
          DistributedMutex.synchronize("akismet_post_#{post.id}") do
            if post.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE] == DiscourseAkismet::Bouncer::PENDING_STATE
              spam_count += 1 if bouncer.perform_check(client, post)
            end
          end
        end

      # Trigger an event that akismet found spam. This allows people to
      # notify chat rooms or whatnot
      DiscourseEvent.trigger(:akismet_found_spam, spam_count) if spam_count > 0
    end
  end
end
