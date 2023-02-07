# frozen_string_literal: true

require "excon"

class Netease
  class Error < StandardError
  end

  class Client
    PLUGIN_NAME = "discourse-akismet".freeze
    MAXIMUM_TEXT_LENGTH = 9999
    NETEASE_CHECK_VERSION = "v5.2".freeze
    NETEASE_FEEDBACK_VERSION = "v2".freeze

    def initialize(api_secret:, business_id:, base_url:)
      @api_secret = api_secret
      @business_id = business_id
      @api_base_url = "http://as.dun.163.com"
      @base_url = base_url
    end

    def self.build_client
      api_secret = { id: SiteSetting.netease_secret_id, key: SiteSetting.netease_secret_key }

      new(
        api_secret: api_secret,
        business_id: SiteSetting.netease_business_id,
        base_url: Discourse.base_url,
      )
    end

    def comment_check(body)
      response = post("v5/text/check", payload_with_signature(body))
      response_body = JSON.parse(response.body)

      if response_body["code"] != 200
        api_error = {
          code: response_body["code"],
          msg: response_body["msg"],
          error: response_body["error"],
        }

        return "error", api_error.compact
      end

      response_body.dig("result", "antispam", "suggestion") != 0 ? "spam" : "ham"
    end

    def submit_feedback(state, body)
      # feedback_list = [{
      #   taskId: body[:netease_task_id],
      #   level: state == "spam" ? 0 : 2
      # }]

      # response = post("v2/text/feedback", body)
      # response_body = response.body

      true
    end

    private

    def self.user_agent_string
      @user_agent_string ||=
        begin
          plugin_version =
            Discourse.plugins.find { |plugin| plugin.name == PLUGIN_NAME }.metadata.version

          "Discourse/#{Discourse::VERSION::STRING} | #{PLUGIN_NAME}/#{plugin_version}"
        end
    end

    def post(path, body)
      response =
        Excon.post(
          "#{@api_base_url}/#{path}",
          body: body.to_query,
          headers: {
            "Content-Type" => "application/x-www-form-urlencoded",
            "User-Agent" => self.class.user_agent_string,
          },
        )

      raise Netease::Error.new(response.status_line) if response.status != 200

      response
    end

    def payload_with_signature(body)
      body[:comment_content] = body[:comment_content].strip[0..MAXIMUM_TEXT_LENGTH] if body[
        :comment_content
      ]

      payload = {
        secretId: @api_secret[:id],
        businessId: @business_id,
        timestamp: Time.now.strftime("%s%L").to_i,
        nonce: SecureRandom.random_number(1_000_000_000_000_0),
        signatureMethod: "MD5",
        dataId: body[:permalink].strip[0..127],
        content: body[:comment_content],
        version: NETEASE_CHECK_VERSION,
      }

      signature_str = ""
      payload.sort.to_h.keys.each { |k| signature_str += k.to_s + payload[k].to_s }

      signature_str << @api_secret[:key]
      signature_str.force_encoding("UTF-8")

      payload[:signature] = Digest::MD5.hexdigest(signature_str)

      payload
    end
  end
end
