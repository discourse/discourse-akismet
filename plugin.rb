# name: discourse-akismet
# about: supports submitting posts to akismet for review
# version: 0.1.0
# authors: Michael Verdi, Robin Ward

# install dependencies
gem "akismet", "1.0.2"

# load the engine
load File.expand_path('../lib/discourse_akismet.rb', __FILE__)
load File.expand_path('../lib/discourse_akismet/engine.rb', __FILE__)

# Admin UI
register_asset "javascripts/admin/mod_queue_admin.js", :admin

# UI
register_asset "stylesheets/mod_queue_styles.scss"

after_initialize do
  require_dependency File.expand_path('../jobs/check_for_spam_posts.rb', __FILE__)
  require_dependency File.expand_path('../jobs/update_akismet_status.rb', __FILE__)

  # Store extra data for akismet
  DiscourseEvent.on(:post_created) do |post, params, user|
    if SiteSetting.akismet_api_key.present?
      post.custom_fields['AKISMET_STATE'] = 'new'
      post.custom_fields['AKISMET_IP_ADDRESS'] = params[:ip_address]
      post.custom_fields['AKISMET_USER_AGENT'] = params[:user_agent]
      post.custom_fields['AKISMET_REFERRER'] = params[:referrer]
      post.save_custom_fields
    end
  end
end

# And mount the engine
Discourse::Application.routes.append do
  mount ::DiscourseAkismet::Engine, at: '/akismet'
end
