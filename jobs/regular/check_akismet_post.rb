# frozen_string_literal: true

module Jobs
  class CheckAkismetPost < ::Jobs::Base
    def execute(args)
      return if !SiteSetting.akismet_enabled?
      return if !(post = Post.find_by(id: args[:post_id], user_deleted: false))
      return if Reviewable.exists?(target: post)

      DistributedMutex.synchronize("akismet_post_#{post.id}") do
        if post.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE] ==
             DiscourseAkismet::Bouncer::PENDING_STATE
          DiscourseAkismet::PostsBouncer.new.perform_check(
            DiscourseAkismet::AntiSpamService.client,
            post,
          )
        end
      end
    end
  end
end
