module DiscourseAkismet

  def self.with_client
    Akismet::Client.open(SiteSetting.akismet_api_key,
      Discourse.base_url,
      :app_name => 'Discourse',
      :app_version => Discourse::VERSION::STRING ) do |client|
        yield client
    end
  end

  def self.args_for_post(post)
    [post.custom_fields['AKISMET_IP_ADDRESS'],
     post.custom_fields['AKISMET_USER_AGENT'],
     {
       content_type: 'forum-post',
       referrer: post.custom_fields['AKISMET_REFERRER'],
       permalink: "#{Discourse.base_url}#{post.url}",
       comment_author: post.user.username,
       comment_content: post.raw
     }]
  end

  def self.needs_review
    post_ids = PostCustomField.where(name: 'AKISMET_STATE', value: 'needs_review').pluck(:post_id)
    posts = Post.with_deleted.where(id: post_ids)
  end

  def self.move_to_state(post, state, opts=nil)
    opts ||= {}
    return if post.blank? || SiteSetting.akismet_api_key.blank?

    post.custom_fields['AKISMET_STATE'] = state

    # Optional parameters to set
    post.custom_fields['AKISMET_IP_ADDRESS'] = opts[:ip_address] if opts[:ip_address].present?
    post.custom_fields['AKISMET_USER_AGENT'] = opts[:user_agent] if opts[:user_agent].present?
    post.custom_fields['AKISMET_REFERRER'] = opts[:referrer] if opts[:referrer].present?

    post.save_custom_fields
  end

end
