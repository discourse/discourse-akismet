module Jobs
  class CheckAkismetPost < Jobs::Base

    # Check a single post for spam. We do this for TL0 to get a faster response
    # without batching.
    def execute(args)
      raise Discourse::InvalidParameters.new(:post_id) unless args[:post_id].present?
      return unless SiteSetting.akismet_enabled?

      post = Post.where(id: args[:post_id], user_deleted: false).first
      return unless post.present?

      DiscourseAkismet.check_for_spam(post)
    end
  end
end
