# frozen_string_literal: true

module DiscourseAkismet
  class AntiSpamService
    def self.client
      return if !SiteSetting.akismet_enabled?

      netease? ? Netease::Client.build_client : Akismet::Client.build_client
    end

    def self.args_manager
      netease? ? Netease::RequestArgs : Akismet::RequestArgs
    end

    def self.api_secret_configured?
      if netease?
        SiteSetting.netease_secret_id.present? && SiteSetting.netease_secret_key.present? &&
          SiteSetting.netease_business_id.present?
      else
        SiteSetting.akismet_api_key.present?
      end
    end

    def self.api_secret_blank?
      !api_secret_configured?
    end

    def self.netease?
      SiteSetting.anti_spam_service == "netease"
    end
  end
end
