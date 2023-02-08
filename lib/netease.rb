# frozen_string_literal: true

require "excon"

class Netease
  MAXIMUM_CONTENT_LENGTH = 9999

  class Error < StandardError
  end

  class RequestArgs
    def initialize(target, munger = nil)
      @target = target
      @munger = munger
    end

    def for_check
      send("for_#{target_name}_check")
    end

    def for_feedback
      { feedback: { taskId: @target.custom_fields["NETEASE_TASK_ID"] } }
    end

    private

    def for_post_check
      args = {
        dataId: "post-#{@target.id}",
        content: post_content&.strip[0..MAXIMUM_CONTENT_LENGTH],
      }

      @munger.call(args) if @munger

      args
    end

    def for_user_check
      bio = @target.user_profile&.bio_raw

      args = { dataId: "user-#{@target.id}", content: bio&.strip[0..MAXIMUM_CONTENT_LENGTH] }

      @munger.call(args) if @munger

      args
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
    PLUGIN_NAME = "discourse-akismet"
    CHECK_VERSION = "v5.2"
    FEEDBACK_VERSION = "v2"
    FEEDBACK_PATH = "v2/text/feedback"
    CHECK_PATH = "v5/text/check"
    API_BASE_URL = "http://as.dun.163.com"
    HASH_ALGORITHM = "MD5"
    NONCE_UPPER_BOUND = 100_000 * 100_000 * 10

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
      payload = body.merge(comment_check_base_payload)
      payload[:signature] = signature(payload)

      response = post(CHECK_PATH, payload)
      response_body =
        begin
          JSON.parse(response.body)
        rescue JSON::ParserError
          {}
        end

      if response_body["code"] != 200
        api_error = {
          code: response_body["code"].to_s,
          msg: response_body["msg"],
          error: response_body["msg"],
        }

        return "error", api_error.compact
      end

      anti_spam_result = response_body.dig("result", "antispam") || {}
      task_id = anti_spam_result["taskId"]

      # TODO(selase) This should handled in caller. Quick hack to ensure interface compatibility for now
      target_name, id = body[:dataId].split("-")
      log_task_id(target_name, id.to_i, task_id)

      anti_spam_result["suggestion"] != 0 ? "spam" : "ham"
    end

    def submit_feedback(state, body)
      feedback = body[:feedback]

      return false if feedback[:taskId].blank?

      payload = {}
      feedback.merge!(level: state == "ham" ? 0 : 2)
      payload = feedback_base_payload
      payload[:feedbacks] = JSON.dump([feedback])
      payload[:signature] = signature(payload)

      response = post(FEEDBACK_PATH, payload)
      response_body =
        begin
          JSON.parse(response.body)
        rescue JSON::ParserError
          {}
        end

      raise Netease::Error.new(response_body["msg"]) if response_body["code"] != 200

      true
    end

    def base_payload
      {
        secretId: @api_secret[:id],
        businessId: @business_id,
        timestamp: Time.now.strftime("%s%L").to_i,
        nonce: nonce,
        signatureMethod: HASH_ALGORITHM,
      }
    end

    def nonce
      SecureRandom.random_number(NONCE_UPPER_BOUND)
    end

    def comment_check_base_payload
      base_payload.merge(version: CHECK_VERSION)
    end

    def feedback_base_payload
      base_payload.merge(version: FEEDBACK_VERSION)
    end

    private

    def log_task_id(target_name, id, task_id)
      return if %w[user post].exclude?(target_name)

      target =
        if target_name == "user"
          User.find_by(id: id)
        else
          Post.with_deleted.find_by(id: id)
        end

      target.upsert_custom_fields("NETEASE_TASK_ID" => task_id) if target
    end

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
          "#{API_BASE_URL}/#{path}",
          body: body.to_query,
          headers: {
            "Content-Type" => "application/x-www-form-urlencoded",
            "User-Agent" => self.class.user_agent_string,
          },
        )

      raise Netease::Error.new(response.status_line) if [200, 201].exclude?(response.status)

      response
    end
  end
end
