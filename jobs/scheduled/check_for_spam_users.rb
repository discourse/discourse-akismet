# frozen_string_literal: true

module Jobs
  class CheckForSpamUsers < ::Jobs::Scheduled
    every 10.minutes

    def execute(args)
      return unless SiteSetting.akismet_enabled?
      return if SiteSetting.akismet_api_key.blank?

      bouncer = DiscourseAkismet::UsersBouncer.new
      client = Akismet::Client.build_client

      DiscourseAkismet::UsersBouncer.to_check
        .includes(:user_profile)
        .find_each do |user|
        DistributedMutex.synchronize("akismet_user_#{user.id}") do
          if user.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE] == 'new'
            bouncer.perform_check(client, user)
          end
        end
      end
    end
  end
end
