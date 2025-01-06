# frozen_string_literal: true

module DiscourseDev
  class ReviewableAkismetUser < DiscourseDev::Reviewable
    def populate!
      users = @users.sample(2)

      spam_user = users.pop
      errored_user = users.pop

      spam_user.tap do |user|
        reviewable =
          ::ReviewableAkismetUser.needs_review!(
            target: user,
            reviewable_by_moderator: true,
            created_by: Discourse.system_user,
            payload: {
              username: user.username,
              name: user.name,
              email: user.email,
              bio: user.user_profile.bio_raw,
            },
          )
        reviewable.add_score(
          Discourse.system_user,
          PostActionType.types[:spam],
          created_at: reviewable.created_at,
          reason: "akismet_spam_user",
          force_review: true,
        )
      end

      errored_user.tap do |user|
        reviewable =
          ::ReviewableAkismetUser.needs_review!(
            target: user,
            reviewable_by_moderator: true,
            created_by: Discourse.system_user,
            payload: {
              username: user.username,
              name: user.name,
              email: user.email,
              bio: user.user_profile.bio_raw,
              external_error: {
                error: "some_error_code",
                code: 500,
                msg: "akismet failed to check this user",
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
