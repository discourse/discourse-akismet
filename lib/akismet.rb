# frozen_string_literal: true

require "excon"

class Akismet
  class Error < StandardError
  end

  class RequestArgs
    def initialize(target, munger = nil)
      @target = target
      @munger = munger
    end

    def for_check
      send("for_#{target_name}")
    end

    def for_feedback
      send("for_#{target_name}")
    end

    private

    def for_user
      profile = @target.user_profile
      token = @target.user_auth_token_logs.last

      extra_args = {
        blog: Discourse.base_url,
        content_type: "signup",
        permalink: "#{Discourse.base_url}/u/#{@target.username_lower}",
        comment_author: @target.username,
        comment_content: profile&.bio_raw,
        comment_author_url: profile&.website,
        user_ip: token&.client_ip&.to_s,
        user_agent: token&.user_agent,
      }

      # Sending the email to akismet is optional
      extra_args[:comment_author_email] = @target.email if SiteSetting.akismet_transmit_email?
      @munger.call(extra_args) if @munger

      extra_args
    end

    def for_post
      extra_args = {
        blog: Discourse.base_url,
        content_type: @target.is_first_post? ? "forum-post" : "reply",
        referrer: @target.custom_fields["AKISMET_REFERRER"],
        permalink: "#{Discourse.base_url}#{@target.url}",
        comment_author: @target.user.try(:username),
        comment_content: post_content,
        comment_author_url: @target.user&.user_profile&.website,
        user_ip: @target.custom_fields["AKISMET_IP_ADDRESS"],
        user_agent: @target.custom_fields["AKISMET_USER_AGENT"],
      }

      # Sending the email to akismet is optional
      if SiteSetting.akismet_transmit_email?
        extra_args[:comment_author_email] = @target.user.try(:email)
      end
      @munger.call(extra_args) if @munger

      extra_args
    end

    def target_name
      @target.class.to_s.downcase
    end

    def post_content
      return if !@target.is_a?(Post)
      return @target.raw if !@target.is_first_post?

      topic = @target.topic || Topic.with_deleted.find_by(id: @target.topic_id)
      "#{topic && topic.title}\n\n#{@target.raw}"
    end
  end

  class Client
    PLUGIN_NAME = "discourse-akismet".freeze
    VALID_COMMENT_CHECK_RESPONSE = %w[true false].each(&:freeze)
    VALID_SUBMIT_RESPONSE = "Thanks for making the web a better place.".freeze
    UNKNOWN_ERROR_MESSAGE = "Unknown error".freeze
    DEBUG_HEADER = "X-akismet-debug-help".freeze
    ERROR_HEADER = "X-akismet-error".freeze
    INVALID_CREDENTIALS = "Invalid credentials".freeze

    def initialize(api_key:, base_url:)
      @api_url = "https://#{api_key}.rest.akismet.com/1.1"
      @base_url = base_url
    end

    def self.build_client
      new(api_key: SiteSetting.akismet_api_key, base_url: Discourse.base_url)
    end

    def comment_check(body)
      response = post("comment-check", body)
      response_body = response.body

      if response.is_a?(Excon::Response) && response.get_header(ERROR_HEADER)
        api_error = {}
        api_error[:error] = response.get_header("X-akismet-error")
        api_error[:code] = response.get_header("X-akismet-alert-code")
        api_error[:msg] = response.get_header("X-akismet-alert-msg")

        return "error", api_error.compact
      end

      if !VALID_COMMENT_CHECK_RESPONSE.include?(response_body)
        debug_help =
          if response_body == "invalid"
            INVALID_CREDENTIALS
          else
            response.headers[DEBUG_HEADER] || UNKNOWN_ERROR_MESSAGE
          end

        raise Akismet::Error.new(debug_help)
      end

      response_body == VALID_COMMENT_CHECK_RESPONSE.first ? "spam" : "ham"
    end

    def submit_feedback(state, body)
      return false if body[:comment_content].blank?

      response = post("submit-#{state}", body)
      response_body = response.body

      raise Akismet::Error.new(UNKNOWN_ERROR_MESSAGE) if response_body != VALID_SUBMIT_RESPONSE

      true
    end

    private

    # From https://akismet.com/development/api/#detailed-docs
    #  If possible, your user agent string should always use the following format:
    #  Application Name/Version | Plugin Name/Version
    def self.user_agent_string
      @user_agent_string ||=
        begin
          plugin_version =
            Discourse.plugins.find { |plugin| plugin.name == PLUGIN_NAME }.metadata.version

          "Discourse/#{Discourse::VERSION::STRING} | #{PLUGIN_NAME}/#{plugin_version}"
        end
    end

    def post(path, body)
      # Send a maximum of 32000 chars which is the default for
      # maximum post length site settings.
      body[:comment_content] = body[:comment_content].strip[0..31_999] if body[:comment_content]

      response =
        Excon.post(
          "#{@api_url}/#{path}",
          body: body.merge(blog: @base_url).to_query,
          headers: {
            "Content-Type" => "application/x-www-form-urlencoded",
            "User-Agent" => self.class.user_agent_string,
          },
        )

      raise Akismet::Error.new(response.status_line) if response.status != 200

      response
    end
  end
end
