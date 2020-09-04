# frozen_string_literal: true

module DiscourseAkismet

  def self.with_client
    Logster.logger.error("[akismet] opening client to #{SiteSetting.akismet_api_key}")
    begin
      Logster.logger.error("[akismet] Global setting #{GlobalSetting.akismet_api_key}")
    rescue
    end
    Akismet::Client.open(SiteSetting.akismet_api_key,
      Discourse.base_url,
      :app_name => 'Discourse',
      :app_version => Discourse::VERSION::STRING ) do |client|
        yield client
    end
  end

  def self.args_for_post(post)
    extra_args = {
      content_type: 'forum-post',
      referrer: post.custom_fields['AKISMET_REFERRER'],
      permalink: "#{Discourse.base_url}#{post.url}",
      comment_author: post.user.username,
      comment_content: post.raw
    }

    # Sending the email to akismet is optional
    if SiteSetting.akismet_transmit_email?
      extra_args[:comment_author_email] = post.user.email
    end

    [post.custom_fields['AKISMET_IP_ADDRESS'],
     post.custom_fields['AKISMET_USER_AGENT'],
     extra_args]
  end

  def self.to_check
    PostCustomField.where(name: 'AKISMET_STATE', value: 'new')
                   .where('posts.id IS NOT NULL')
                   .includes(:post)
                   .references(:post)
  end

  def self.check_for_spam(to_check)
    return if to_check.blank?

    spam_count = 0
    DiscourseAkismet.with_client do |client|
      [to_check].flatten.each do |post|
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

  def self.stats
    result = PostCustomField.where(name: 'AKISMET_STATE').group(:value).count.symbolize_keys!
    result[:confirmed_spam] ||= 0
    result[:confirmed_ham] ||= 0
    result[:needs_review] ||= 0
    result[:checked] ||= 0
    result[:scanned] = result[:checked] + result[:needs_review] + result[:confirmed_spam] + result[:confirmed_ham]
    result
  end

  def self.needs_review
    post_ids = PostCustomField.where(name: 'AKISMET_STATE', value: 'needs_review').pluck(:post_id)
    posts = Post.with_deleted.where(id: post_ids).includes(:topic).references(:topic)
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
