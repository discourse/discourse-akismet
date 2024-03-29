# frozen_string_literal: true

require_dependency "reviewable"

class ReviewableAkismetUser < Reviewable
  def build_actions(actions, guardian, _args)
    return [] unless pending?

    build_action(actions, :not_spam, icon: "thumbs-up")

    if guardian.is_staff?
      # TODO: Remove after the 2.8 release
      if respond_to?(:delete_user_actions)
        delete_user_actions(actions)
      else
        build_action(
          actions,
          :reject_spam_user_delete,
          icon: "trash-alt",
          confirm: true,
          button_class: "btn-danger",
        )
      end
    end
  end

  # Reviewable#perform should be used instead of these action methods.
  # These are only part of the public API because #perform needs them to be public.

  def perform_not_spam(performed_by, _args)
    bouncer.submit_feedback(target, "ham")
    log_confirmation(performed_by, "confirmed_ham")

    successful_transition :rejected, :disagreed
  end

  def perform_delete_user(performed_by, args)
    if target && Guardian.new(performed_by).can_delete_user?(target)
      log_confirmation(performed_by, "confirmed_spam_deleted")
      bouncer.submit_feedback(target, "spam")
      Jobs.enqueue(
        :confirm_akismet_flagged_posts,
        user_id: target.id,
        performed_by_id: performed_by.id,
      )

      opts = user_deletion_opts(performed_by, args)
      UserDestroyer.new(performed_by).destroy(target, opts)
    end

    successful_transition :deleted, :agreed
  end

  def perform_delete_user_block(performed_by, args)
    perform_delete_user(performed_by, args.merge(block_ip: true, block_email: true))
  end
  alias perform_reject_spam_user_delete perform_delete_user_block
  # TODO: Remove after the 2.8 release

  private

  def bouncer
    DiscourseAkismet::UsersBouncer.new
  end

  def successful_transition(to_state, update_flag_status)
    create_result(:success, to_state) do |result|
      result.update_flag_stats = { status: update_flag_status, user_ids: [created_by_id] }
    end
  end

  def build_action(actions, id, icon:, bundle: nil, confirm: false, button_class: nil)
    actions.add(id, bundle: bundle) do |action|
      action.icon = icon
      action.label = "js.akismet.#{id}"
      action.confirm_message = "js.akismet.reviewable_delete_prompt" if confirm
      action.button_class = button_class
    end
  end

  def user_deletion_opts(performed_by, args)
    {
      context: I18n.t("akismet.delete_reason", performed_by: performed_by.username),
      delete_posts: true,
      delete_as_spammer: true,
      quiet: true,
      block_ip: !!args[:block_ip],
      block_email: !!args[:block_email],
    }
  end

  def log_confirmation(performed_by, custom_type)
    StaffActionLogger.new(performed_by).log_custom(custom_type)
  end

  def post
  end
end
