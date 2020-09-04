# frozen_string_literal: true

module Jobs
  class UpdateAkismetStatus < Jobs::Base

    def execute(args)
      raise Discourse::InvalidParameters.new(:post_id) unless args[:post_id].present?
      raise Discourse::InvalidParameters.new(:status) unless args[:status].present?

      return unless SiteSetting.akismet_enabled?

      post = Post.with_deleted.where(id: args[:post_id]).first
      return unless post.present?

      DiscourseAkismet.with_client do |client|
        if args[:status] == 'ham'
          client.submit_ham(*DiscourseAkismet.args_for_post(post))
        elsif args[:status] == 'spam'
          client.submit_spam(*DiscourseAkismet.args_for_post(post))
        end
      end
    end
  end
end
