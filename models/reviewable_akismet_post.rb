# frozen_string_literal: true

require_dependency "reviewable"

class ReviewableAkismetPost < Reviewable
  include ReviewableActionBuilder

  def self.action_aliases
    { confirm_suspend: :confirm_spam }
  end

  def build_combined_actions(actions, guardian, _args)
    return [] unless pending?

    agree_bundle =
      actions.add_bundle("#{id}-agree", icon: "thumbs-up", label: "reviewables.actions.agree.title")

    delete_user_actions(actions, agree_bundle) if guardian.can_delete_user?(target_created_by)

    build_action(
      actions,
      :confirm_spam,
      icon: "trash-can",
      bundle: agree_bundle,
      has_description: true,
    )

    if guardian.can_suspend?(target_created_by)
      build_action(
        actions,
        :confirm_suspend,
        icon: "ban",
        bundle: agree_bundle,
        client_action: "suspend",
        has_description: true,
      )
    end

    disagree_bundle =
      actions.add_bundle(
        "#{id}-disagree",
        icon: "thumbs-down",
        label: "reviewables.actions.disagree_bundle.title",
      )

    build_action(
      actions,
      :not_spam,
      icon: "thumbs-down",
      bundle: disagree_bundle,
      has_description: true,
    )
    build_action(actions, :ignore, icon: "xmark", bundle: disagree_bundle, has_description: true)
  end

  def post
    @post ||= (target || Post.with_deleted.find_by(id: target_id))
  end

  # Reviewable#perform should be used instead of these action methods.
  # These are only part of the public API because #perform needs them to be public.

  def perform_confirm_spam(performed_by, _args)
    bouncer.submit_feedback(post, "spam")
    log_confirmation(performed_by, "confirmed_spam")

    # Double-check the original post is deleted
    PostDestroyer.new(performed_by, post).destroy unless post.deleted_at?

    successful_transition :approved, :agreed
  end

  def perform_not_spam(performed_by, _args)
    bouncer.submit_feedback(post, "ham")
    log_confirmation(performed_by, "confirmed_ham")

    if post.deleted_at
      PostDestroyer.new(performed_by, post).recover
      if SiteSetting.akismet_notify_user? && post.reload.topic
        SystemMessage.new(post.user).create(
          "akismet_not_spam",
          topic_title: post.topic.title,
          post_link: post.full_url,
        )
      end
    end

    successful_transition :rejected, :disagreed
  end

  def perform_ignore(performed_by, _args)
    log_confirmation(performed_by, "ignored")

    successful_transition :ignored, :ignored
  end

  def perform_delete_user(performed_by, args)
    if Guardian.new(performed_by).can_delete_user?(target_created_by)
      bouncer.submit_feedback(post, "spam")
      log_confirmation(performed_by, "confirmed_spam_deleted")

      PostDestroyer.new(performed_by, post).destroy unless post.deleted_at?

      opts = user_deletion_opts(performed_by, args)
      email = target_created_by.email
      UserDestroyer.new(performed_by).destroy(target_created_by, opts)

      message = UserNotifications.account_deleted(email, self)
      Email::Sender.new(message, :account_deleted).send
    end

    successful_transition :deleted, :agreed
  end

  def perform_delete_user_block(performed_by, args)
    perform_delete_user(performed_by, args.merge(block_email: true, block_ip: true))
  end
  alias perform_confirm_delete perform_delete_user_block
  # TODO: Remove after the 2.8 release

  private

  def bouncer
    DiscourseAkismet::PostsBouncer.new
  end

  def successful_transition(to_state, update_flag_status)
    create_result(:success, to_state) do |result|
      result.update_flag_stats = { status: update_flag_status, user_ids: [created_by_id] }
    end
  end

  def build_action(
    actions,
    id,
    icon:,
    bundle: nil,
    confirm: false,
    button_class: nil,
    client_action: nil,
    has_description: true
  )
    actions.add(id, bundle: bundle) do |action|
      action.icon = icon
      action.label = "js.akismet.#{id}"
      action.description = "js.akismet.#{id}_description" if has_description
      action.confirm_message = "js.akismet.reviewable_delete_prompt" if confirm
      action.client_action = client_action
      action.button_class = button_class
    end
  end

  def user_deletion_opts(performed_by, args)
    {
      context: I18n.t("akismet.delete_reason", performed_by: performed_by.username),
      delete_posts: true,
      block_urls: true,
      delete_as_spammer: true,
      block_email: !!args[:block_email],
      block_ip: !!args[:block_ip],
    }
  end

  def log_confirmation(performed_by, custom_type)
    StaffActionLogger.new(performed_by).log_custom(
      custom_type,
      post_id: post.id,
      topic_id: post.topic_id,
    )
  end
end
