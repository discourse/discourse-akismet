# frozen_string_literal: true

# name: discourse-akismet
# about: Fights spam with Akismet, an algorithm used by millions of sites to combat spam automatically.
# meta_topic_id: 109337
# version: 0.1.0
# authors: Michael Verdi, Robin Ward
# url: https://github.com/discourse/discourse-akismet

enabled_site_setting :akismet_enabled

require_relative "lib/discourse_akismet/anti_spam_service.rb"
require_relative "lib/discourse_akismet/bouncer.rb"
require_relative "lib/discourse_akismet/engine.rb"
require_relative "lib/discourse_akismet/post_voting_comments_bouncer.rb"
require_relative "lib/discourse_akismet/posts_bouncer.rb"
require_relative "lib/discourse_akismet/users_bouncer.rb"
require_relative "lib/akismet.rb"
require_relative "lib/netease.rb"

register_asset "stylesheets/akismet.scss"

after_initialize do
  require_relative "lib/discourse_dev/reviewable_akismet_post"
  require_relative "jobs/regular/check_akismet_post.rb"
  require_relative "jobs/regular/check_akismet_post_voting_comment.rb"
  require_relative "jobs/regular/check_akismet_user.rb"
  require_relative "jobs/regular/confirm_akismet_flagged_posts.rb"
  require_relative "jobs/regular/update_akismet_status.rb"
  require_relative "jobs/scheduled/check_for_spam_post_voting_comments.rb"
  require_relative "jobs/scheduled/check_for_spam_posts.rb"
  require_relative "jobs/scheduled/check_for_spam_users.rb"
  require_relative "jobs/scheduled/clean_old_akismet_custom_fields.rb"
  require_relative "lib/user_destroyer_extension.rb"
  require_relative "models/reviewable_akismet_post_voting_comment.rb"
  require_relative "models/reviewable_akismet_post.rb"
  require_relative "models/reviewable_akismet_user.rb"

  if Rails.env.local? &&
       DiscoursePluginRegistry.respond_to?(:discourse_dev_populate_reviewable_types)
    require_relative "lib/discourse_dev/reviewable_akismet_post.rb"
    require_relative "lib/discourse_dev/reviewable_akismet_user.rb"

    if defined?(SiteSetting.post_voting_enabled) && SiteSetting.post_voting_enabled?
      require_relative "lib/discourse_dev/reviewable_akismet_post_voting_comment.rb"
      DiscoursePluginRegistry.discourse_dev_populate_reviewable_types.add DiscourseDev::ReviewableAkismetPostVotingComment
    end
  end

  require_relative "serializers/reviewable_akismet_post_voting_comment_serializer.rb"
  require_relative "serializers/reviewable_akismet_post_serializer.rb"
  require_relative "serializers/reviewable_akismet_user_serializer.rb"

  register_reviewable_type ReviewableAkismetPost
  register_reviewable_type ReviewableAkismetUser
  register_reviewable_type ReviewableAkismetPostVotingComment

  # TODO(roman): Remove else branch after 3.0 release.
  if respond_to?(:register_user_destroyer_on_content_deletion_callback)
    register_user_destroyer_on_content_deletion_callback(
      Proc.new do |user, guardian, opts|
        if opts[:delete_as_spammer]
          ReviewableFlaggedPost
            .where(target_created_by: user)
            .find_each do |reviewable|
              # The overriden `agree_with_flags` handles this reviewables, this
              # method just ensures that feedback is submitted.
              if target = Post.with_deleted.find_by(id: reviewable.target_id)
                DiscourseAkismet::PostsBouncer.new.submit_feedback(target, "spam")
              end
            end

          ReviewableAkismetPost
            .where(target_created_by: user)
            .find_each do |reviewable|
              # Ensure that reviewable was not handled already
              #
              # Performing `delete_user` action sends feedback to Akismet, destroys
              # the user and then updates reviewable status. This method is called
              # before reviewable status is updated which means that the same action
              # will be called twice.
              if UserHistory.where(
                   custom_type: "confirmed_spam_deleted",
                   post_id: reviewable.target_id,
                 ).exists?
                next
              end

              # Confirming an Akismet reviewable automatically sends feedback
              if reviewable.actions_for(guardian).has?(:confirm_spam)
                reviewable.perform(guardian.user, :confirm_spam)
              end
            end
        elsif opts[:delete_posts]
          ReviewableAkismetPost.where(target_created_by: user).destroy_all
        end
      end,
    )
  else
    reloadable_patch { UserDestroyer.prepend(DiscourseAkismet::UserDestroyerExtension) }
  end

  TopicView.add_post_custom_fields_allowlister do |user|
    user&.staff? ? [DiscourseAkismet::Bouncer::AKISMET_STATE] : []
  end

  add_model_callback(UserProfile, :before_save) do
    if (bio_raw_changed? && bio_raw.present?) || (website_changed? && website.present?)
      DiscourseAkismet::UsersBouncer.new.enqueue_for_check(user)
    end
  end

  add_to_serializer(:post, :akismet_state, include_condition: -> { scope.is_staff? }) do
    post_custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]
  end

  on(:post_created) do |post, params|
    DiscourseAkismet::PostsBouncer
      .new
      .check(post) { |bouncer| bouncer.store_additional_information(post, params) }
  end

  on(:post_edited) do |post, _, revisor|
    next unless revisor.reviewable_content_changed?

    editor = post.last_editor
    next if editor.is_system_user? || !editor.regular?

    DiscourseAkismet::PostsBouncer.new.check(post)
  end

  on(:post_recovered) do |post, _, _|
    # Ensure that posts that were deleted and thus skipped are eventually
    # checked.
    if post.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE] !=
         DiscourseAkismet::Bouncer::SKIPPED_STATE
      next
    end

    DiscourseAkismet::PostsBouncer.new.check(post)
  end

  on(:post_voting_comment_created) do |comment, params|
    DiscourseAkismet::PostVotingCommentsBouncer
      .new
      .check(comment) { |bouncer| bouncer.store_additional_information(comment, params) }
  end

  on(:post_voting_comment_edited) do |comment, user, revisor|
    old_comment = PostVotingComment.find(comment.id)
    next if comment.raw == old_comment.raw

    editor = comment.last_editor
    next if editor.is_system_user? || !editor.regular?

    DiscourseAkismet::PostVotingCommentsBouncer.new.check(comment)
  end

  # If a user is anonymized, support anonymizing their IPs
  on(:user_anonymized) do |args|
    user = args[:user]
    opts = args[:opts]

    if user && opts && opts.has_key?(:anonymize_ip)
      anonymize_posts = <<~SQL
        UPDATE post_custom_fields AS pcf
         SET value = :new_ip
         FROM posts AS p
         WHERE name = 'AKISMET_IP_ADDRESS'
           AND p.id = pcf.post_id
           AND p.user_id = :user_id
      SQL

      args = { user_id: user.id, new_ip: opts[:anonymize_ip] }

      DB.exec anonymize_posts, args

      if defined?(SiteSetting.post_voting_enabled) && SiteSetting.post_voting_enabled?
        anonymize_post_voting_comments = <<~SQL
        UPDATE post_voting_comment_custom_fields AS pvccf
         SET value = :new_ip
         FROM post_voting_comments AS pvc
         WHERE name = 'AKISMET_IP_ADDRESS'
           AND pvc.id = pvccf.post_voting_comment_id
           AND pvc.user_id = :user_id
        SQL

        DB.exec anonymize_post_voting_comments, args
      end
    end
  end

  staff_actions = %i[confirmed_spam confirmed_ham ignored confirmed_spam_deleted]
  extend_list_method(UserHistory, :staff_actions, staff_actions)

  add_reviewable_score_link(:akismet_spam_post, "plugin:discourse-akismet")
  add_reviewable_score_link(:akismet_spam_user, "plugin:discourse-akismet")

  if Rails.env.local? &&
       DiscoursePluginRegistry.respond_to?(:discourse_dev_populate_reviewable_types)
    DiscoursePluginRegistry.discourse_dev_populate_reviewable_types.add DiscourseDev::ReviewableAkismetPost
    DiscoursePluginRegistry.discourse_dev_populate_reviewable_types.add DiscourseDev::ReviewableAkismetUser
  end
end
