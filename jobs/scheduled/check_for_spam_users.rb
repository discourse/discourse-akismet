# frozen_string_literal: true

module Jobs
  class CheckForSpamUsers < ::Jobs::Scheduled
    every SiteSetting.spam_check_interval_mins.minutes

    def execute(args)
      return unless SiteSetting.akismet_enabled?
      return if DiscourseAkismet::AntiSpamService.api_secret_blank?

      bouncer = DiscourseAkismet::UsersBouncer.new
      client = DiscourseAkismet::AntiSpamService.client

      DiscourseAkismet::UsersBouncer
        .to_check
        .includes(:user_profile)
        .find_each do |user|
          DistributedMutex.synchronize("akismet_user_#{user.id}") do
            if user.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE] ==
                 DiscourseAkismet::Bouncer::PENDING_STATE
              bouncer.perform_check(client, user)
            end
          end
        end
    end
  end
end
