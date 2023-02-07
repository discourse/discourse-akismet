# frozen_string_literal: true

require "rails_helper"

describe Netease do
  let(:client) { Netease::Client.build_client }

  let(:post_args) do
    {
      content_type: "forum-post",
      permalink: "http://test.localhost/t/this-is-a-test-topic-49/1889/1",
      comment_author: "bruce106",
      comment_content: "This is a test topic 49\n\nHello world",
      comment_author_email: "bruce106@wayne.com",
    }
  end

  before do
    SiteSetting.netease_secret_id = "secret_id"
    SiteSetting.netease_secret_key = "secret_key"
    SiteSetting.netease_business_id = "business_id"
  end

  describe "#comment_check" do
    it "returns 'spam' spam posts" do
      stub_request(:post, "http://as.dun.163.com/v5/text/check").to_return(
        status: 200,
        body: {
          code: 200,
          msg: "ok",
          result: {
            antispam: {
              taskId: "fx6sxdcd89fvbvg4967b4787d78a",
              dataId: "dataId",
              suggestion: 1,
            },
          },
        }.to_json,
      )

      expect(client.comment_check(post_args)).to eq("spam")
    end

    it "returns 'ham' non-spam posts" do
      stub_request(:post, "http://as.dun.163.com/v5/text/check").to_return(
        status: 200,
        body: {
          code: 200,
          msg: "ok",
          result: {
            antispam: {
              taskId: "fx6sxdcd89fvbvg4967b4787d78a",
              dataId: "dataId",
              suggestion: 0,
            },
          },
        }.to_json,
      )

      expect(client.comment_check(post_args)).to eq("ham")
    end

    it "returns error details for error responses" do
      stub_request(:post, "http://as.dun.163.com/v5/text/check").to_return(
        status: 200,
        body: { code: 401, msg: "Invalid business Id" }.to_json,
      )

      expect(client.comment_check(post_args)).to eq(
        ["error", { code: 401, msg: "Invalid business Id" }],
      )
    end
  end
end
