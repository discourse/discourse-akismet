# frozen_string_literal: true

require_dependency "reviewable"

class ReviewableAkismetPostVotingComment < Reviewable
  include ReviewableActionBuilder

  def serializer
    ReviewableAkismetPostVotingCommentSerializer
  end

  def self.action_aliases
    { confirm_suspend: :confirm_spam }
  end

  def flagged_by_user_ids
    @flagged_by_user_ids ||= reviewable_scores.map(&:user_id)
  end

  def post
    nil
  end

  def comment
    @comment ||= (target || PostVotingComment.with_deleted.find_by(id: target_id))
  end

  def comment_creator
    @comment_creator ||= User.find_by(id: comment.user_id)
  end

  def build_combined_actions(actions, guardian, _args)
    return [] unless pending?

    agree =
      actions.add_bundle("#{id}-agree", icon: "thumbs-up", label: "reviewables.actions.agree.title")

    build_action(actions, :confirm_spam, icon: "trash-can", bundle: agree, has_description: true)

    if guardian.can_suspend?(comment_creator)
      build_action(
        actions,
        :confirm_suspend,
        icon: "ban",
        bundle: agree,
        client_action: "suspend",
        has_description: true,
      )
    end

    delete_user_actions(actions, agree) if guardian.can_delete_user?(comment_creator)

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

  def perform_confirm_spam(performed_by, args)
    agree(performed_by) { comment.trash!(performed_by) }
  end

  def perform_not_spam(performed_by, args)
    disagree(performed_by) { comment.recover! if comment.deleted_at }
  end

  def perform_disagree(performed_by, args)
    disagree(performed_by)
  end

  def perform_ignore(performed_by, args)
    ignore(performed_by)
  end

  def perform_delete_user(performed_by, args)
    if Guardian.new(performed_by).can_delete_user?(comment.user)
      bouncer.submit_feedback(comment, "spam")
      log_confirmation(performed_by, "confirmed_spam_deleted")

      comment.trash!(performed_by) unless comment.deleted_at?

      opts = user_deletion_opts(performed_by, args)

      UserDestroyer.new(performed_by).destroy(comment.user, opts)
    end

    successful_transition :deleted, :agreed
  end

  def perform_delete_user_block(performed_by, args)
    perform_delete_user(performed_by, args.merge(block_email: true, block_ip: true))
  end

  private

  def bouncer
    DiscourseAkismet::PostVotingCommentsBouncer.new
  end

  def log_confirmation(performed_by, custom_type)
    StaffActionLogger.new(performed_by).log_custom(
      custom_type,
      comment_id: comment.id,
      post_id: comment.post_id,
      topic_id: comment.post.topic_id,
    )
  end

  def agree(performed_by)
    bouncer.submit_feedback(comment, "spam")
    log_confirmation(performed_by, "confirmed_spam")

    yield if block_given?
    create_result(:success, :approved) do |result|
      result.update_flag_stats = { status: :agreed, user_ids: flagged_by_user_ids }
      result.recalculate_score = true
    end
  end

  def disagree(performed_by)
    bouncer.submit_feedback(comment, "ham")
    log_confirmation(performed_by, "confirmed_ham")
    yield if block_given?

    UserSilencer.unsilence(comment_creator)

    create_result(:success, :rejected) do |result|
      result.update_flag_stats = { status: :disagreed, user_ids: flagged_by_user_ids }
      result.recalculate_score = true
    end
  end

  def ignore(performed_by)
    log_confirmation(performed_by, "ignored")
    yield if block_given?
    successful_transition(:ignored, :ignored)
    create_result(:success, :ignored) do |result|
      result.update_flag_stats = { status: :ignored, user_ids: flagged_by_user_ids }
    end
  end

  def build_action(
    actions,
    id,
    icon:,
    button_class: nil,
    bundle: nil,
    client_action: nil,
    confirm: false,
    has_description: true
  )
    actions.add(id, bundle: bundle) do |action|
      action.icon = icon
      action.button_class = button_class
      action.label = "js.akismet.#{id}"
      action.description = "js.akismet.#{id}_description" if has_description
      action.client_action = client_action
      action.confirm_message = "js.akismet.reviewable_delete_prompt" if confirm
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

  def successful_transition(to_state, update_flag_status)
    create_result(:success, to_state) do |result|
      result.update_flag_stats = { status: update_flag_status, user_ids: flagged_by_user_ids }
    end
  end
end
