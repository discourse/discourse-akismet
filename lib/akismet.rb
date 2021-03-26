# frozen_string_literal: true

require 'excon'

class Akismet
  class Error < StandardError; end

  class Client
    PLUGIN_NAME = 'discourse-akismet'.freeze
    VALID_COMMENT_CHECK_RESPONSE = %w{true false}.each(&:freeze)
    VALID_SUBMIT_RESPONSE = 'Thanks for making the web a better place.'.freeze
    UNKNOWN_ERROR_MESSAGE = 'Unknown error'.freeze
    DEBUG_HEADER = 'X-akismet-debug-help'.freeze
    ERROR_HEADER = 'X-akismet-error'.freeze
    INVALID_CREDENTIALS = "Invalid credentials".freeze

    def initialize(api_key:, base_url:)
      @api_url =  "https://#{api_key}.rest.akismet.com/1.1"
      @base_url = base_url
    end

    def self.build_client
      new(api_key: SiteSetting.akismet_api_key, base_url: Discourse.base_url)
    end

    def comment_check(body)
      response = post('comment-check', body)
      response_body = response.body

      if (response.is_a?(Excon::Response) && response.get_header(ERROR_HEADER))
        api_error = {}
        api_error[:error] = response.get_header('X-akismet-error')
        api_error[:code]  = response.get_header('X-akismet-alert-code')
        api_error[:msg]   = response.get_header('X-akismet-alert-msg')

        return 'error', api_error.compact
      end

      if !(VALID_COMMENT_CHECK_RESPONSE.include?(response_body))
        debug_help =
          if response_body == "invalid"
            INVALID_CREDENTIALS
          else
            response.headers[DEBUG_HEADER] || UNKNOWN_ERROR_MESSAGE
          end

        raise Akismet::Error.new(debug_help)
      end

      response_body == VALID_COMMENT_CHECK_RESPONSE.first ? 'spam' : 'ham'
    end

    def submit_feedback(state, body)
      return false if body[:comment_content].blank?

      response = post("submit-#{state}", body)
      response_body = response.body

      if response_body != VALID_SUBMIT_RESPONSE
        raise Akismet::Error.new(UNKNOWN_ERROR_MESSAGE)
      end

      true
    end

    private

    # From https://akismet.com/development/api/#detailed-docs
    #  If possible, your user agent string should always use the following format:
    #  Application Name/Version | Plugin Name/Version
    def self.user_agent_string
      @user_agent_string ||= begin
        plugin_version = Discourse.plugins.find do |plugin|
          plugin.name == PLUGIN_NAME
        end.metadata.version

        "Discourse/#{Discourse::VERSION::STRING} | #{PLUGIN_NAME}/#{plugin_version}"
      end
    end

    def post(path, body)
      # Send a maximum of 32000 chars which is the default for
      # maximum post length site settings.
      if body[:comment_content]
        body[:comment_content] = body[:comment_content].strip[0..31999]
      end

      response = Excon.post("#{@api_url}/#{path}",
        body: body.merge(blog: @base_url).to_query,
        headers: {
          'Content-Type' => 'application/x-www-form-urlencoded',
          'User-Agent' => self.class.user_agent_string
        }
      )

      if response.status != 200
        raise Akismet::Error.new(response.status_line)
      end

      response
    end
  end
end
