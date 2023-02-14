# frozen_string_literal: true

module DiscourseAkismet
  class UsersBouncer < Bouncer
    def self.to_check
      User
        .joins("INNER JOIN user_custom_fields ucf ON  users.id = ucf.user_id")
        .where(trust_level: TrustLevel[0])
        .where("ucf.name = ?", AKISMET_STATE)
        .where(
          "ucf.value = 'pending' OR (ucf.value = 'skipped' AND users.created_at > ?)",
          1.day.ago,
        )
    end

    def suspect?(user)
      SiteSetting.akismet_review_users? && user.trust_level === TrustLevel[0] &&
        (user.user_profile.bio_raw.present? || user.user_profile.website.present?) &&
        user.user_auth_token_logs&.last&.client_ip.present?
    end

    def args_for(user, action)
      args = AntiSpamService.args_manager.new(user)

      action == "check" ? args.for_check : args.for_feedback
    end

    private

    def enqueue_job(user)
      Jobs.enqueue(:check_akismet_user, user_id: user.id)
    end

    def before_check(user)
      should_check?(user)
    end

    def mark_as_spam(user)
      reviewable =
        ReviewableAkismetUser.needs_review!(
          target: user,
          reviewable_by_moderator: true,
          created_by: spam_reporter,
          payload: {
            username: user.username,
            name: user.name,
            email: user.email,
            bio: user.user_profile.bio_raw,
          },
        )

      add_score(reviewable, "akismet_spam_user")
      move_to_state(user, "confirmed_spam")
    end

    def mark_as_errored(user, reason)
      super do
        ReviewableAkismetUser.needs_review!(
          target: user,
          reviewable_by_moderator: true,
          created_by: spam_reporter,
          payload: {
            username: user.username,
            name: user.name,
            email: user.email,
            bio: user.user_profile.bio_raw,
            external_error: reason,
          },
        )
      end
    end
  end
end
