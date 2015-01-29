module Jobs
  class CheckForSpamPosts < ::Jobs::Scheduled
    every 10.minutes

    def execute(args)
      Logster.logger.info("[akismet] beginning job")

      return if SiteSetting.akismet_api_key.blank?
      new_posts = PostCustomField.where(name: 'AKISMET_STATE', value: 'new').where('posts.id IS NOT NULL').includes(:post).references(:post)

      if new_posts.any?

        spam_count = 0
        DiscourseAkismet.with_client do |client|
          new_posts.each do |pcf|
            post = pcf.post
            spam = client.comment_check(
              post.custom_fields['AKISMET_IP_ADDRESS'],
              post.custom_fields['AKISMET_USER_AGENT'],
              {
                content_type: 'comment',
                referrer: post.custom_fields['AKISMET_REFERRER'],
                permalink: "#{Discourse.base_url}#{post.url}",
                comment_author: post.user.username,
                comment_author_email: post.user.email,
                comment_content: post.raw
              })

            # If the post is spam, mark it for review and destroy it
            if spam
              PostDestroyer.new(Discourse.system_user, post).destroy
              spam_count += 1
              post.custom_fields['AKISMET_STATE'] = 'needs_review'
            else
              post.custom_fields['AKISMET_STATE'] = 'checked'
            end

            # Update the state
            post.save_custom_fields
          end
        end

        # Trigger an event that akismet found spam. This allows people to
        # notify chat rooms or whatnot
        DiscourseEvent.trigger(:akismet_found_spam, spam_count) if spam_count > 0
      end

    end

  end
end
