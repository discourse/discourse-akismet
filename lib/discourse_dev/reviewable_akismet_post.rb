# frozen_string_literal: true

module DiscourseDev
  class ReviewableAkismetPost < DiscourseDev::Reviewable
    def populate!
      posts = @posts.sample(2)

      spam_post = posts.pop
      errored_post = posts.pop

      spam_post.tap do |post|
        reviewable =
          ::ReviewableAkismetPost.needs_review!(
            created_by: Discourse.system_user,
            target: post,
            topic: post.topic,
            reviewable_by_moderator: true,
            payload: {
              post_cooked: post.cooked,
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

      errored_post.tap do |post|
        reviewable =
          ::ReviewableAkismetPost.needs_review!(
            created_by: Discourse.system_user,
            target: post,
            topic: post.topic,
            reviewable_by_moderator: true,
            payload: {
              post_cooked: post.cooked,
              external_error: {
                error: "some_error_code",
                code: 500,
                msg: "akismet failed to check this post",
              },
            },
          )
        reviewable.add_score(
          Discourse.system_user,
          PostActionType.types[:spam],
          created_at: reviewable.created_at,
          reason: "akismet_server_error",
          force_review: true,
        )
      end
    end
  end
end
