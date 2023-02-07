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

  describe "#submit_feedback" do
    it "does not submit feedback if `comment_content` is empty" do
      expect(client.submit_feedback("spam", {})).to eq(false)
    end

    shared_examples "sends feedback to NetEase and handles the response" do
      it "returns true" do
        stub_request(:post, "http://as.dun.163.com/v2/text/feedback").to_return(
          status: 200,
          body: {
            code: 200,
            msg: "ok",
            result: [{ taskId: "qabd8230ed003ac2baeeeffc59cde946", result: 0 }],
          }.to_json,
        )

        expect(client.submit_feedback(feedback, post_args)).to eq(true)
      end

      it "raises error for error response" do
        stub_request(:post, "http://as.dun.163.com/v2/text/feedback").to_return(
          status: 200,
          body: { code: 401, msg: "Invalid business ID", result: [] }.to_json,
        )

        expect { client.submit_feedback(feedback, post_args) }.to raise_error(
          Netease::Error,
          "Invalid business ID",
        )
      end
    end

    context "with spam" do
      let(:feedback) { "spam" }

      it_behaves_like "sends feedback to NetEase and handles the response"
    end

    context "with ham" do
      let(:feedback) { "ham" }

      it_behaves_like "sends feedback to NetEase and handles the response"
    end
  end
end
