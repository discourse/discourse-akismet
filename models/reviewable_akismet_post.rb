# frozen_string_literal: true

require_dependency 'reviewable'

class ReviewableAkismetPost < Reviewable
  def self.action_aliases
    { confirm_suspend: :confirm_spam }
  end

  def build_actions(actions, guardian, _args)
    return [] unless pending?

    agree = actions.add_bundle("#{id}-agree", icon: 'thumbs-up', label: 'reviewables.actions.agree.title')

    build_action(actions, :confirm_spam, icon: 'check', bundle: agree, has_description: true)

    if guardian.can_suspend?(target_created_by)
      build_action(actions, :confirm_suspend, icon: 'ban', bundle: agree, client_action: 'suspend', has_description: true)
    end

    if guardian.can_delete_user?(target_created_by)
      # TODO: Remove after the 2.8 release
      if respond_to?(:delete_user_actions)
        delete_user_actions(actions)
      else
        build_action(actions, :confirm_delete, icon: 'trash-alt', bundle: agree, confirm: true)
      end
    end

    build_action(actions, :not_spam, icon: 'thumbs-down')
    build_action(actions, :ignore, icon: 'external-link-alt')
  end

  def post
    @post ||= (target || Post.with_deleted.find_by(id: target_id))
  end

  # Reviewable#perform should be used instead of these action methods.
  # These are only part of the public API because #perform needs them to be public.

  def perform_confirm_spam(performed_by, _args)
    bouncer.submit_feedback(post, 'spam')
    log_confirmation(performed_by, 'confirmed_spam')

    # Double-check the original post is deleted
    PostDestroyer.new(performed_by, post).destroy unless post.deleted_at?

    successful_transition :approved, :agreed
  end

  def perform_not_spam(performed_by, _args)
    bouncer.submit_feedback(post, 'ham')
    log_confirmation(performed_by, 'confirmed_ham')

    if post.deleted_at
      PostDestroyer.new(performed_by, post).recover
      if SiteSetting.akismet_notify_user? && post.reload.topic
        SystemMessage.new(post.user).create('akismet_not_spam', topic_title: post.topic.title, post_link: post.full_url)
      end
    end

    successful_transition :rejected, :disagreed
  end

  def perform_ignore(performed_by, _args)
    log_confirmation(performed_by, 'ignored')

    successful_transition :ignored, :ignored
  end

  def perform_delete_user(performed_by, args)
    if Guardian.new(performed_by).can_delete_user?(target_created_by)
      bouncer.submit_feedback(post, 'spam')
      log_confirmation(performed_by, 'confirmed_spam_deleted')

      PostDestroyer.new(performed_by, post).destroy unless post.deleted_at?

      opts = user_deletion_opts(performed_by, args)
      UserDestroyer.new(performed_by).destroy(target_created_by, opts)
    end

    successful_transition :deleted, :agreed
  end

  def perform_delete_user_block(performed_by, args)
    perform_delete_user(performed_by, args.merge(block_email: true, block_ip: true))
  end
  alias :perform_confirm_delete :perform_delete_user_block
  # TODO: Remove after the 2.8 release

  private

  def bouncer
    DiscourseAkismet::PostsBouncer.new
  end

  def successful_transition(to_state, update_flag_status)
    create_result(:success, to_state)  do |result|
      result.update_flag_stats = { status: update_flag_status, user_ids: [created_by_id] }
    end
  end

  def build_action(actions, id, icon:, bundle: nil, confirm: false, button_class: nil, client_action: nil, has_description: true)
    actions.add(id, bundle: bundle) do |action|
      action.icon = icon
      action.label = "js.akismet.#{id}"
      action.description = "js.akismet.#{id}_description" if has_description
      action.confirm_message = 'js.akismet.reviewable_delete_prompt' if confirm
      action.client_action = client_action
      action.button_class = button_class
    end
  end

  def user_deletion_opts(performed_by, args)
    {
      context: I18n.t('akismet.delete_reason', performed_by: performed_by.username),
      delete_posts: true,
      block_urls: true,
      delete_as_spammer: true,
      block_email: !!args[:block_email],
      block_ip: !!args[:block_ip]
    }
  end

  def log_confirmation(performed_by, custom_type)
    StaffActionLogger.new(performed_by).log_custom(custom_type,
      post_id: post.id,
      topic_id: post.topic_id
    )
  end
end
