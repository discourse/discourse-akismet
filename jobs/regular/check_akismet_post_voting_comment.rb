# frozen_string_literal: true

module Jobs
  class CheckAkismetPostVotingComment < ::Jobs::Base
    def execute(args)
      return unless SiteSetting.akismet_enabled?
      return unless comment = PostVotingComment.find_by(id: args[:comment_id])
      return if Reviewable.exists?(target: comment)

      DistributedMutex.synchronize("akismet_post_voting_comment_#{comment.id}") do
        if comment.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE] == "pending"
          DiscourseAkismet::PostVotingCommentsBouncer.new.perform_check(
            DiscourseAkismet::AntiSpamService.client,
            comment,
          )
        end
      end
    end
  end
end
