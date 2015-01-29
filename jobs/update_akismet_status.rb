module Jobs
  class UpdateAkismetStatus < Jobs::Base

    def execute(args)
      raise Discourse::InvalidParameters.new(:post_id) unless args[:post_id].present?
      raise Discourse::InvalidParameters.new(:status) unless args[:status].present?

      post = Post.with_deleted.where(id: args[:post_id]).first
      return unless post.present?

      DiscourseAkismet.with_client do |client|
        client.submit_ham(
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
      end

    end
  end
end

