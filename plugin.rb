# name: discourse-akismet
# about: supports submitting posts to akismet for review
# version: 0.1.0
# authors: Michael Verdi, Robin Ward
# url: https://github.com/discourse/discourse-akismet

enabled_site_setting :akismet_enabled

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
  on(:post_created) do |post, params|
    if DiscourseAkismet.should_check_post?(post)
      DiscourseAkismet.move_to_state(post, 'new', params)

      # Enqueue checks for TL0 posts faster
      Jobs.enqueue(:check_akismet_post, post_id: post.id) if post.user.trust_level == 0
    end
  end

  # When staff agrees a flagged post is spam, send it to akismet
  on(:confirmed_spam_post) do |post|
    if SiteSetting.akismet_enabled?
      Jobs.enqueue(:update_akismet_status, post_id: post.id, status: 'spam')
    end
  end

  add_to_class(:guardian, :can_review_akismet?) do
    user.try(:staff?)
  end

  add_to_serializer(:current_user, :akismet_review_count) do
    scope.can_review_akismet? ? DiscourseAkismet.needs_review.count : nil
  end

  # We use `DiscourseEvent` here because we want it called even when disabled
  DiscourseEvent.on(:build_wizard) do |wizard|

    # Don't ask the user if it's shadowed - a hosting provider might offer akismet with a
    # hidden configuration
    unless SiteSetting.shadowed_settings.include?(:akismet_api_key)

      wizard.append_step('akismet') do |step|
        step.add_field(id: 'akismet_api_key', type: 'text', value: SiteSetting.akismet_api_key)

        step.on_update do |updater|
          updater.apply_settings(:akismet_api_key)
          updater.update_setting(:akismet_enabled, SiteSetting.akismet_api_key.present?)
        end
      end

    end
  end
end

add_admin_route 'akismet.title', 'akismet'

# And mount the engine
Discourse::Application.routes.append do
  mount ::DiscourseAkismet::Engine, at: '/admin/plugins/akismet'
end
