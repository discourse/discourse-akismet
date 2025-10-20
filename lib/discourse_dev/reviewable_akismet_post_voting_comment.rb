# frozen_string_literal: true

module DiscourseDev
  class ReviewableAkismetPostVotingComment < DiscourseDev::Reviewable
    def populate!
      topic = Topic.new.create!
      topic.update_column(:subtype, ::Topic::POST_VOTING_SUBTYPE)
      post = topic.posts.first
      comment =
        PostVotingComment.create!(
          user: @users.sample,
          post: post,
          raw: "This is a comment for post #{post.id}",
        )

      reviewable =
        ::ReviewableAkismetPostVotingComment.needs_review!(
          created_by: Discourse.system_user,
          target: comment,
          topic: topic,
          reviewable_by_moderator: true,
          target_created_by: comment.user,
          payload: {
            comment_cooked: comment.cooked,
          },
        )
      reviewable.add_score(
        Discourse.system_user,
        PostActionType.types[:spam],
        created_at: reviewable.created_at,
        reason: "akismet_spam_post",
        force_review: true,
      )
    end
  end
end
