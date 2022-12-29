# frozen_string_literal: true

module Jobs
  class CheckAkismetPost < ::Jobs::Base
    def execute(args)
      return unless SiteSetting.akismet_enabled?
      return unless post = Post.find_by(id: args[:post_id], user_deleted: false)
      return if Reviewable.exists?(target: post)

      DistributedMutex.synchronize("akismet_post_#{post.id}") do
        if post.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE] == "pending"
          DiscourseAkismet::PostsBouncer.new.perform_check(Akismet::Client.build_client, post)
        end
      end
    end
  end
end
