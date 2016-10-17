require 'excon'

class Akismet
  class Error < StandardError; end

  class Client
    PLUGIN_NAME = 'discourse-akismet'.freeze
    VALID_COMMENT_CHECK_RESPONSE = %w{true false}.each(&:freeze)
    VALID_SUBMIT_RESPONSE = 'Thanks for making the web a better place.'.freeze
    UNKNOWN_ERROR_MESSAGE = 'Unknown error'.freeze
    DEBUG_HEADER = 'X-akismet-debug-help'.freeze

    def initialize(api_key:, base_url:)
      @api_url =  "https://#{api_key}.rest.akismet.com/1.1"
      @base_url = base_url
    end

    def self.with_client(api_key:, base_url:)
      client = self.new(api_key: api_key, base_url: base_url)
      yield client if block_given?
    end

    def comment_check(body)
      response = post('comment-check', body)
      response_body = response.body

      if !(VALID_COMMENT_CHECK_RESPONSE.include?(response_body))
        debug_help = response.headers[DEBUG_HEADER] || UNKNOWN_ERROR_MESSAGE
        raise Akismet::Error.new(debug_help)
      end

      response_body == VALID_COMMENT_CHECK_RESPONSE.first
    end

    def submit_spam(body)
      submit_feedback('submit-spam', body)
    end

    def submit_ham(body)
      submit_feedback('submit-ham', body)
    end

    private

    def submit_feedback(method, body)
      response = post(method, body)
      response_body = response.body

      if response_body != VALID_SUBMIT_RESPONSE
        raise Akismet::Error.new(UNKNOWN_ERROR_MESSAGE)
      end

      true
    end

    # From https://akismet.com/development/api/#detailed-docs
    #  If possible, your user agent string should always use the following format:
    #  Application Name/Version | Plugin Name/Version
    def self.user_agent_string
      @user_agent_string ||= begin
        plugin_version = Discourse.plugins.find do |plugin|
          plugin.name == PLUGIN_NAME
        end.version

        "Discourse/#{Discourse::VERSION::STRING} | #{PLUGIN_NAME}/#{plugin_version}"
      end
    end

    def post(path, body)
      response = Excon.post("#{@api_url}/#{path}",
        body: body.merge(blog: @base_url).to_query,
        headers: {
          'Content-Type' => 'application/x-www-form-urlencoded',
          'User-Agent' => Akismet::Client.user_agent_string
        }
      )

      if response.status != 200
        raise Akismet::Error.new(response.status_line)
      end

      response
    end
  end
end
