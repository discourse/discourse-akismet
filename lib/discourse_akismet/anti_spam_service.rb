# frozen_string_literal: true

module DiscourseAkismet
  class AntiSpamService
    def self.client
      return if !SiteSetting.akismet_enabled?

      api =
        if SiteSetting.anti_spam_service == "netease"
          Netease::Client
        else
          Akismet::Client
        end

      api.build_client
    end
  end
end
