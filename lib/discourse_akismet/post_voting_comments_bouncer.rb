# frozen_string_literal: true

module DiscourseAkismet
  class PostVotingCommentsBouncer < Bouncer
    CUSTOM_FIELDS = %w[
      AKISMET_STATE
      AKISMET_IP_ADDRESS
      AKISMET_USER_AGENT
      AKISMET_REFERRER
      NETEASE_TASK_ID
    ]

    @@munger = nil

    #check this SQL query
    def self.to_check
      PostVotingComment
        .joins(
          "INNER JOIN post_voting_comment_custom_fields ON post_voting_comments.id = post_voting_comment_custom_fields.post_voting_comment_id",
        )
        .joins(
          "LEFT OUTER JOIN reviewables ON reviewables.target_id = post_voting_comment_custom_fields.post_voting_comment_id",
        )
        .where("post_voting_comment_custom_fields.name = ?", AKISMET_STATE)
        .where("post_voting_comment_custom_fields.value = ?", DiscourseAkismet::Bouncer::PENDING_STATE)
        .where("reviewables.id IS NULL")
        .includes(post: :topic)
        .references(:topic)
    end

    def suspect?(comment)
      if comment.blank? || comment.post.blank? || comment.post.topic.blank? ||
           (!SiteSetting.akismet_enabled?)
        return false
      end

      # We don't run akismet on private messages
      return false if comment.post.topic.private_message?

      stripped = comment.raw.strip

      # We only check posts over 20 chars
      return false if stripped.size < 20

      # Always check the first post of a TL1 user
      if SiteSetting.review_tl1_users_first_post_voting_comment? &&
           comment.user.trust_level == TrustLevel[1] && comment.user.post_count == 0
        return true
      end

      # We only check certain trust levels
      if comment.user.has_trust_level?(TrustLevel[SiteSetting.skip_akismet_trust_level.to_i])
        return false
      end

      # If a user is locked, we don't want to check them forever
      return false if comment.user.post_count > SiteSetting.skip_akismet_posts.to_i

      # If the entire post is a URI we skip it. This might seem counter intuitive but
      # Discourse already has settings for max links and images for new users. If they
      # pass it means the administrator specifically allowed them.
      uri =
        begin
          URI(stripped)
        rescue StandardError
          nil
        end
      return false if uri

      # Otherwise check the post!
      true
    end

    def store_additional_information(comment, opts = {})
      values ||= {}
      return if comment.blank? || AntiSpamService.api_secret_blank?

      # Optional parameters to set
      values["AKISMET_IP_ADDRESS"] = opts[:ip_address] if opts[:ip_address].present?
      values["AKISMET_USER_AGENT"] = opts[:user_agent] if opts[:user_agent].present?
      values["AKISMET_REFERRER"] = opts[:referrer] if opts[:referrer].present?

      comment.upsert_custom_fields(values)
    end

    def clean_old_akismet_custom_fields
      PostVotingCommentCustomField
        .where(name: CUSTOM_FIELDS)
        .where("created_at <= ?", 2.months.ago)
        .delete_all
    end

    def self.munge_args(&block)
      @@munger = block
    end

    def self.reset_munge
      @@munger = nil
    end

    def args_for(comment, action)
      args = AntiSpamService.args_manager.new(comment, @@munger)
      action == "check" ? args.for_check : args.for_feedback
    end

    private

    def enqueue_job(comment)
      Jobs.enqueue(:check_akismet_post_voting_comment, comment_id: comment.id)
    end

    def before_check(comment)
      return true unless comment.post.nil?
      false
    end

    def mark_as_spam(comment)
      comment.trash!

      # Send a message to the user explaining that it happened
      # notify_poster(comment) if SiteSetting.akismet_notify_user?

      reviewable =
        ReviewableAkismetPostVotingComment.needs_review!(
          created_by: spam_reporter,
          target: comment,
          target_created_by: spam_reporter,
          topic: comment.post.topic,
          reviewable_by_moderator: true,
          payload: {
            comment_cooked: comment.cooked,
          },
        )

      add_score(reviewable, "akismet_spam_comment")
      move_to_state(comment, "confirmed_spam")
    end

    def mark_as_errored(comment, reason)
      super do
        ReviewableAkismetPostVotingComment.needs_review!(
          created_by: spam_reporter,
          target: comment,
          target_created_by: spam_reporter,
          topic: comment.post.topic,
          reviewable_by_moderator: true,
          payload: {
            comment_cooked: comment.cooked,
            external_error: reason,
          },
        )
      end
    end

    def comment_content(comment)
      return comment.raw unless comment.is_first_comment?

      topic = comment.post.topic || Topic.with_deleted.find_by(id: comment.post.topic_id)
      "#{topic && topic.title}\n\n#{comment.raw}"
    end
  end
end
