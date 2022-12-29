# frozen_string_literal: true

module DiscourseAkismet::UserDestroyerExtension
  def agree_with_flags(user)
    if SiteSetting.akismet_enabled?
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
          if reviewable.actions_for(@guardian).has?(:confirm_spam)
            reviewable.perform(@actor, :confirm_spam)
          end
        end
    end

    super
  end
end
