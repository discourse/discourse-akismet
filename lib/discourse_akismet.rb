module DiscourseAkismet

  def self.with_client
    Akismet::Client.open(SiteSetting.akismet_api_key,
      Discourse.base_url,
      :app_name => 'Discourse',
      :app_version => Discourse::VERSION::STRING ) do |client|
        yield client
    end
  end

end
