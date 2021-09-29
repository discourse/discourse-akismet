# frozen_string_literal: true

module Jobs
  class CheckAkismetUser < ::Jobs::Base
    def execute(args)
      return unless SiteSetting.akismet_enabled?
      return unless user = User.includes(:user_profile).find_by(id: args[:user_id])
      return if Reviewable.exists?(target: user)

      DistributedMutex.synchronize("akismet_user_#{user.id}") do
        if user.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE] == 'pending'
          DiscourseAkismet::UsersBouncer.new.perform_check(Akismet::Client.build_client, user)
        end
      end
    end
  end
end
