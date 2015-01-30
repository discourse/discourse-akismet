module Jobs
  class CheckForSpamPosts < ::Jobs::Scheduled
    every 10.minutes

    def execute(args)
      return if SiteSetting.akismet_api_key.blank?
      new_posts = PostCustomField.where(name: 'AKISMET_STATE', value: 'new').where('posts.id IS NOT NULL').includes(:post).references(:post)

      if new_posts.any?

        spam_count = 0
        DiscourseAkismet.with_client do |client|
          new_posts.each do |pcf|
            post = pcf.post

            # If the post is spam, mark it for review and destroy it
            if client.comment_check(*DiscourseAkismet.args_for_post(post))
              PostDestroyer.new(Discourse.system_user, post).destroy
              spam_count += 1
              DiscourseAkismet.move_to_state(post, 'needs_review')
            else
              DiscourseAkismet.move_to_state(post, 'checked')
            end
          end
        end

        # Trigger an event that akismet found spam. This allows people to
        # notify chat rooms or whatnot
        DiscourseEvent.trigger(:akismet_found_spam, spam_count) if spam_count > 0
      end

    end

  end
end
