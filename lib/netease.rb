# frozen_string_literal: true

require "excon"

class Netease
  MAXIMUM_CONTENT_LENGTH = 9999

  class Error < StandardError
  end

  class RequestParams
    def initialize(target, munger = nil)
      @target = target
      @munger = munger
    end

    def for_check
      send("for_#{target_name}_check")
    end

    def for_feedback
      send("for_#{target_name}_feedback")
    end

    private

    def for_post_check
      { dataId: "post-#{@target.id}", content: post_content.strip[0..MAXIMUM_CONTENT_LENGTH] }
    end

    def for_user_check
      bio = @target.user_profile&.bio_raw

      { dataId: "user-#{@target.id}", content: bio&.strip[0..MAXIMUM_CONTENT_LENGTH] }
    end

    def for_post_feedback
    end

    def for_user_feedback
    end

    def target_name
      @target.class.to_s.downcase
    end

    def post_content
      return @target.raw unless @target.is_first_post?

      topic = @target.topic || Topic.with_deleted.find_by(id: @target.topic_id)
      "#{topic && topic.title}\n\n#{@target.raw}"
    end
  end

  class Client
    PLUGIN_NAME = "discourse-akismet"
    MAXIMUM_TEXT_LENGTH = 9999
    CHECK_VERSION = "v5.2"
    FEEDBACK_VERSION = "v2"
    FEEDBACK_PATH = "v2/text/feedback"
    CHECK_PATH = "v5/text/check"
    BASE_URL = "http://as.dun.163.com"

    def initialize(api_secret:, business_id:, base_url:)
      @api_secret = api_secret
      @business_id = business_id
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
      response = post(CHECK_PATH, payload_with_signature(body))
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
      return false if body[:comment_content].blank?

      feedback_list = [{ taskId: body[:netease_task_id], level: state == "ham" ? 0 : 2 }]

      payload = {
        secretId: @api_secret[:id],
        businessId: @business_id,
        timestamp: Time.now.strftime("%s%L").to_i,
        nonce: SecureRandom.random_number(1_000_000_000_000_0),
        signatureMethod: "MD5",
        version: FEEDBACK_VERSION,
        feedbacks: JSON.dump(feedback_list),
      }

      payload[:signature] = signature(payload)

      response = post(FEEDBACK_PATH, payload)
      response_body = JSON.parse(response.body)

      raise Netease::Error.new(response_body["msg"]) if response_body["code"] != 200

      true
    end

    private

    def signature(payload)
      signature_str = ""
      payload.sort.to_h.keys.each { |k| signature_str += k.to_s + payload[k].to_s }

      signature_str += @api_secret[:key]
      signature_str.force_encoding("UTF-8")

      Digest::MD5.hexdigest(signature_str)
    end

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
          "#{BASE_URL}/#{path}",
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
        version: CHECK_VERSION,
      }

      payload[:signature] = signature(payload)

      payload
    end
  end
end
