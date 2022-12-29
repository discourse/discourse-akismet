# frozen_string_literal: true

require "rails_helper"

describe Akismet do
  let(:client) { Akismet::Client.new(api_key: "akismetkey", base_url: "someurl") }

  let(:post_args) do
    {
      content_type: "forum-post",
      permalink: "http://test.localhost/t/this-is-a-test-topic-49/1889/1",
      comment_author: "bruce106",
      comment_content: "This is a test topic 49\n\nHello world",
      comment_author_email: "bruce106@wayne.com",
    }
  end

  describe "#comment_check" do
    it "should return 'spam' if the post is spam" do
      stub_request(:post, "https://akismetkey.rest.akismet.com/1.1/comment-check").to_return(
        status: 200,
        body: "true",
      )

      expect(client.comment_check(post_args)).to eq("spam")
    end

    it "should return 'ham' if the post is not spam" do
      stub_request(:post, "https://akismetkey.rest.akismet.com/1.1/comment-check").to_return(
        status: 200,
        body: "false",
      )

      expect(client.comment_check(post_args)).to eq("ham")
    end

    it "should raise an error with the right message if response is not valid" do
      stub_request(:post, "https://akismetkey.rest.akismet.com/1.1/comment-check").to_return(
        status: 200,
        body: "Some unknown error",
        headers: {
          "#{Akismet::Client::DEBUG_HEADER}" => 'Empty "Blog" value',
        },
      )

      expect { client.comment_check(post_args) }.to raise_error(
        Akismet::Error,
        'Empty "Blog" value',
      )

      stub_request(:post, "https://akismetkey.rest.akismet.com/1.1/comment-check").to_return(
        status: 200,
        body: "Some unknown error",
      )

      expect { client.comment_check(post_args) }.to raise_error(
        Akismet::Error,
        Akismet::Client::UNKNOWN_ERROR_MESSAGE,
      )
    end
  end

  describe "#submit_feedback" do
    it "won't submit feedback if `comment_content` is empty" do
      expect(client.submit_feedback("spam", {})).to eq(false)
    end

    shared_examples "sends feedback to Akismet and handles the response" do
      it "should return true" do
        stub_request(:post, "https://akismetkey.rest.akismet.com/1.1/submit-#{feedback}").to_return(
          status: 200,
          body: Akismet::Client::VALID_SUBMIT_RESPONSE,
        )

        expect(client.submit_feedback(feedback, post_args)).to eq(true)
      end

      it "should raise the right error" do
        stub_request(:post, "https://akismetkey.rest.akismet.com/1.1/submit-#{feedback}").to_return(
          status: 200,
          body: "Some error",
        )

        expect { client.submit_feedback(feedback, post_args) }.to raise_error(
          Akismet::Error,
          Akismet::Client::UNKNOWN_ERROR_MESSAGE,
        )
      end
    end

    context "with spam" do
      let(:feedback) { "spam" }

      it_behaves_like "sends feedback to Akismet and handles the response"
    end

    context "with ham" do
      let(:feedback) { "ham" }

      it_behaves_like "sends feedback to Akismet and handles the response"
    end
  end
end
