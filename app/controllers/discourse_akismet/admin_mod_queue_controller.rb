module DiscourseAkismet
  class AdminModQueueController < Admin::AdminController
    def index
      post_ids = PostCustomField.where(name: 'AKISMET_STATE', value: 'needs_review').pluck(:post_id)
      posts = Post.with_deleted.where(id: post_ids)

      render_json_dump({
        posts: serialize_data(posts, PostSerializer),
        enabled: SiteSetting.akismet_api_key.present?
      })
    end

    def confirm_spam
      post = Post.with_deleted.find(params[:post_id])
      post.custom_fields['AKISMET_STATE'] = 'confirmed_spam'
      post.save_custom_fields
      render json: {msg: I18n.t('akismet.spam_confirmed')}
    end

    def allow
      post = Post.with_deleted.find(params[:post_id])

      Jobs.enqueue(:update_akismet_status, post_id: post.id, status: 'ham')

      PostDestroyer.new(current_user, post).recover
      post.custom_fields['AKISMET_STATE'] = 'confirmed_ham'
      post.save_custom_fields

      render json: {msg: I18n.t('akismet.allowed')}
    end

    def delete_user
      post = Post.with_deleted.find(params[:post_id])
      user = post.user
      post.custom_fields['AKISMET_STATE'] = 'confirmed_spam'
      post.save_custom_fields

      UserDestroyer.new(current_user).destroy(user, user_deletion_opts)
      render json: {msg: I18n.t('akismet.deleted_user', username: user.username)}
    end

    private

    def user_deletion_opts
      base = {
        context:           I18n.t('akismet.delete_reason', {performed_by: current_user.username}),
        delete_posts:      true,
        delete_as_spammer: true
      }

      if Rails.env.production? && ENV["Staging"].nil?
        base.merge!({block_email: true, block_ip: true})
      end

      base
    end
  end
end
