# frozen_string_literal: true

# name: discourse-akismet
# about: supports submitting posts to akismet for review
# version: 0.1.0
# authors: Michael Verdi, Robin Ward
# url: https://github.com/discourse/discourse-akismet
# transpile_js: true

enabled_site_setting :akismet_enabled

require_relative 'lib/discourse_akismet/bouncer.rb'
require_relative 'lib/discourse_akismet/engine.rb'
require_relative 'lib/discourse_akismet/posts_bouncer.rb'
require_relative 'lib/discourse_akismet/users_bouncer.rb'
require_relative 'lib/akismet.rb'

register_asset "stylesheets/akismet.scss"

after_initialize do
  require_relative 'jobs/regular/check_akismet_post.rb'
  require_relative 'jobs/regular/check_akismet_user.rb'
  require_relative 'jobs/regular/confirm_akismet_flagged_posts.rb'
  require_relative 'jobs/regular/update_akismet_status.rb'
  require_relative 'jobs/scheduled/check_for_spam_posts.rb'
  require_relative 'jobs/scheduled/check_for_spam_users.rb'
  require_relative 'jobs/scheduled/clean_old_akismet_custom_fields.rb'
  require_relative 'lib/user_destroyer_extension.rb'
  require_relative 'models/reviewable_akismet_post.rb'
  require_relative 'models/reviewable_akismet_user.rb'
  require_relative 'serializers/reviewable_akismet_post_serializer.rb'
  require_relative 'serializers/reviewable_akismet_user_serializer.rb'

  register_reviewable_type ReviewableAkismetPost
  register_reviewable_type ReviewableAkismetUser

  # TODO(roman): Remove else branch after 3.0 release.
  if respond_to?(:register_user_destroyer_on_content_deletion_callback)
    register_user_destroyer_on_content_deletion_callback(
      Proc.new do |user, guardian, opts|
        if opts[:delete_as_spammer]
          ReviewableFlaggedPost.where(target_created_by: user).find_each do |reviewable|
            # The overriden `agree_with_flags` handles this reviewables, this
            # method just ensures that feedback is submitted.
            if target = Post.with_deleted.find_by(id: reviewable.target_id)
              DiscourseAkismet::PostsBouncer.new.submit_feedback(target, 'spam')
            end
          end

          ReviewableAkismetPost.where(target_created_by: user).find_each do |reviewable|
            # Ensure that reviewable was not handled already
            #
            # Performing `delete_user` action sends feedback to Akismet, destroys
            # the user and then updates reviewable status. This method is called
            # before reviewable status is updated which means that the same action
            # will be called twice.
            next if UserHistory.where(custom_type: 'confirmed_spam_deleted', post_id: reviewable.target_id).exists?

            # Confirming an Akismet reviewable automatically sends feedback
            reviewable.perform(guardian.user, :confirm_spam) if reviewable.actions_for(guardian).has?(:confirm_spam)
          end
        end
      end
    )
  else
    reloadable_patch do |plugin|
      UserDestroyer.class_eval { prepend DiscourseAkismet::UserDestroyerExtension }
    end
  end

  TopicView.add_post_custom_fields_allowlister do |user|
    user&.staff? ? [DiscourseAkismet::Bouncer::AKISMET_STATE] : []
  end

  add_model_callback(UserProfile, :before_save) do
    if (bio_raw_changed? && bio_raw.present?) || (website_changed? && website.present?)
      DiscourseAkismet::UsersBouncer.new.enqueue_for_check(user)
    end
  end

  add_to_serializer(:post, :akismet_state, false) do
    post_custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]
  end

  add_to_serializer(:post, :include_akismet_state?) do
    scope.is_staff?
  end

  def check_post(bouncer, post)
    if post.user.trust_level == 0
      # Enqueue checks for TL0 posts faster
      bouncer.enqueue_for_check(post)
    else
      # Otherwise, mark the post to be checked in the next batch
      bouncer.move_to_state(post, 'pending')
    end
  end

  on(:post_created) do |post, params|
    bouncer = DiscourseAkismet::PostsBouncer.new
    if bouncer.should_check?(post)
      # Store extra data for akismet
      bouncer.store_additional_information(post, params)
      check_post(bouncer, post)
    end
  end

  on(:post_edited) do |post, _, _|
    bouncer = DiscourseAkismet::PostsBouncer.new

    if post.last_editor.regular? && bouncer.should_check?(post)
      check_post(bouncer, post)
    end
  end

  on(:post_recovered) do |post, _, _|
    # Ensure that posts that were deleted and thus skipped are eventually
    # checked.
    next if post.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE] != 'skipped'

    bouncer = DiscourseAkismet::PostsBouncer.new
    check_post(bouncer, post) if bouncer.should_check?(post)
  end

  # If a user is anonymized, support anonymizing their IPs
  on(:user_anonymized) do |args|
    user = args[:user]
    opts = args[:opts]

    if user && opts && opts.has_key?(:anonymize_ip)
      sql = <<~SQL
        UPDATE post_custom_fields AS pcf
         SET value = :new_ip
         FROM posts AS p
         WHERE name = 'AKISMET_IP_ADDRESS'
           AND p.id = pcf.post_id
           AND p.user_id = :user_id
      SQL

      args = { user_id: user.id, new_ip: opts[:anonymize_ip] }

      DB.exec sql, args
    end
  end

  staff_actions = %i[confirmed_spam confirmed_ham ignored confirmed_spam_deleted]
  extend_list_method(UserHistory, :staff_actions, staff_actions)

  add_reviewable_score_link(:akismet_spam_post, 'plugin:discourse-akismet')
  add_reviewable_score_link(:akismet_spam_user, 'plugin:discourse-akismet')
end
