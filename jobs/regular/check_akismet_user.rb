# frozen_string_literal: true

module Jobs
  class CheckAkismetUser < ::Jobs::Base
    def execute(args)
      return if !SiteSetting.akismet_enabled?
      return if !(user = User.includes(:user_profile).find_by(id: args[:user_id]))
      return if Reviewable.exists?(target: user)

      DistributedMutex.synchronize("akismet_user_#{user.id}") do
        if user.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE] ==
             DiscourseAkismet::Bouncer::PENDING_STATE
          DiscourseAkismet::UsersBouncer.new.perform_check(
            DiscourseAkismet::AntiSpamService.client,
            user,
          )
        end
      end
    end
  end
end
