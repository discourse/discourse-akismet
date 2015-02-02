# name: discourse-akismet
# about: supports submitting posts to akismet for review
# version: 0.1.0
# authors: Michael Verdi, Robin Ward

# install dependencies
gem "akismet", "1.0.2"

# load the engine
load File.expand_path('../lib/discourse_akismet.rb', __FILE__)
load File.expand_path('../lib/discourse_akismet/engine.rb', __FILE__)

register_asset "stylesheets/mod_queue_styles.scss"

after_initialize do
  require_dependency File.expand_path('../jobs/check_for_spam_posts.rb', __FILE__)
  require_dependency File.expand_path('../jobs/check_akismet_post.rb', __FILE__)
  require_dependency File.expand_path('../jobs/update_akismet_status.rb', __FILE__)

  # Store extra data for akismet
  DiscourseEvent.on(:post_created) do |post, params|
    unless post.user.has_trust_level?(TrustLevel[SiteSetting.skip_akismet_trust_level])
      DiscourseAkismet.move_to_state(post, 'new', params)

      # Enqueue checks for TL0 posts faster
      Jobs.enqueue(:check_akismet_post, post_id: post.id) if post.user.trust_level == 0
    end
  end

  # If a post has been confirmed as spam, send it to Akismet
  DiscourseEvent.on(:confirmed_spam_post) do |post|
    Jobs.enqueue(:update_akismet_status, post_id: post.id, status: 'spam')
  end
end

# And mount the engine
Discourse::Application.routes.append do
  mount ::DiscourseAkismet::Engine, at: '/admin/akismet'
end
