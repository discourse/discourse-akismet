# frozen_string_literal: true

module DiscourseAkismet
  class PostsBouncer < Bouncer
    CUSTOM_FIELDS = %w[
      AKISMET_STATE
      AKISMET_IP_ADDRESS
      AKISMET_USER_AGENT
      AKISMET_REFERRER
      NETEASE_TASK_ID
    ]
    TOPIC_DELETED_CHANNEL = "/discourse-akismet/topic-deleted/"

    @@munger = nil

    def self.to_check
      Post
        .joins("INNER JOIN post_custom_fields ON posts.id = post_custom_fields.post_id")
        .joins("LEFT OUTER JOIN reviewables ON reviewables.target_id = post_custom_fields.post_id")
        .where("post_custom_fields.name = ?", AKISMET_STATE)
        .where("post_custom_fields.value = ?", "pending")
        .where("reviewables.id IS NULL")
        .includes(:topic)
        .references(:topic)
    end

    def suspect?(post)
      if !SiteSetting.akismet_enabled? || post.blank? || post.topic.blank? ||
           post.topic.private_message?
        return false
      end

      stripped_post_raw = post.raw.strip

      return false if stripped_post_raw.size < 20

      # Always check the first post of a TL1 user
      if SiteSetting.review_tl1_users_first_post? && post.user.trust_level == TrustLevel[1] &&
           post.user.post_count.zero?
        return true
      end

      return false if post.user.in_any_groups?(SiteSetting.skip_akismet_groups_map)
      return false if post.user.post_count > SiteSetting.skip_akismet_posts.to_i

      # If the entire post is a URI we skip it. This might seem counter intuitive but
      # Discourse already has settings for max links and images for new users. If they
      # pass it means the administrator specifically allowed them.
      uri =
        begin
          URI(stripped_post_raw)
        rescue StandardError
          nil
        end
      return false if uri

      # Otherwise check the post!
      true
    end

    def store_additional_information(post, opts = {})
      values ||= {}
      return if post.blank? || AntiSpamService.api_secret_blank?

      # Optional parameters to set
      values["AKISMET_IP_ADDRESS"] = opts[:ip_address] if opts[:ip_address].present?
      values["AKISMET_USER_AGENT"] = opts[:user_agent] if opts[:user_agent].present?
      values["AKISMET_REFERRER"] = opts[:referrer] if opts[:referrer].present?

      post.upsert_custom_fields(values)
    end

    def clean_old_akismet_custom_fields
      PostCustomField.where(name: CUSTOM_FIELDS).where("created_at <= ?", 2.months.ago).delete_all
    end

    def self.munge_args(&block)
      @@munger = block
    end

    def self.reset_munge
      @@munger = nil
    end

    def args_for(post, action)
      args = AntiSpamService.args_manager.new(post, @@munger)

      action == "check" ? args.for_check : args.for_feedback
    end

    private

    def enqueue_job(post)
      Jobs.enqueue(:check_akismet_post, post_id: post.id)
    end

    def before_check(post)
      return true unless post.user_deleted? || post.topic.nil?
      false
    end

    def mark_as_spam(post)
      PostDestroyer.new(spam_reporter, post).destroy

      # Send a message to the user explaining that it happened
      notify_poster(post) if SiteSetting.akismet_notify_user?

      if post.is_first_post?
        MessageBus.publish([TOPIC_DELETED_CHANNEL, post.topic_id].join, "spam_found")
      end

      reviewable =
        ReviewableAkismetPost.needs_review!(
          created_by: spam_reporter,
          target: post,
          topic: post.topic,
          reviewable_by_moderator: true,
          payload: {
            post_cooked: post.cooked,
          },
        )

      add_score(reviewable, "akismet_spam_post")
      move_to_state(post, "confirmed_spam")
    end

    def mark_as_errored(post, reason)
      super do
        ReviewableAkismetPost.needs_review!(
          created_by: spam_reporter,
          target: post,
          topic: post.topic,
          reviewable_by_moderator: true,
          payload: {
            post_cooked: post.cooked,
            external_error: reason,
          },
        )
      end
    end

    def notify_poster(post)
      SystemMessage.new(post.user).create(
        "akismet_spam",
        topic_title: post.topic.title,
        post_link: post.full_url,
      )
    end

    def comment_content(post)
      return post.raw unless post.is_first_post?

      topic = post.topic || Topic.with_deleted.find_by(id: post.topic_id)
      "#{topic && topic.title}\n\n#{post.raw}"
    end
  end
end
