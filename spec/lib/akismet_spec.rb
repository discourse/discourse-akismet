# frozen_string_literal: true

require "rails_helper"

describe Akismet do
  fab!(:user) { Fabricate(:active_user) }
  fab!(:post) { Fabricate(:post) }
  let(:client) { Akismet::Client.new(api_key: "akismetkey", base_url: "someurl") }

  let(:user_args) do
    {
      blog: Discourse.base_url,
      content_type: "signup",
      permalink: "#{Discourse.base_url}/u/#{user.username_lower}",
      comment_author: user.username,
      comment_content: user.user_profile&.bio_raw,
      comment_author_url: nil,
      user_ip: nil,
      user_agent: nil,
      comment_author_email: user.email,
      comment_date_gmt: user.created_at.iso8601,
    }
  end

  let(:post_args) do
    {
      blog: Discourse.base_url,
      content_type: "forum-post",
      referrer: nil,
      permalink: "#{Discourse.base_url}#{post.url}",
      comment_author: post.user.username,
      comment_content: "#{post.topic.title}\n\nHello world",
      comment_author_url: nil,
      user_ip: nil,
      user_agent: nil,
      comment_author_email: post.user.email,
      comment_date_gmt: post.created_at.iso8601,
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

  describe "request args" do
    def args_for(target)
      Akismet::RequestArgs.new(target)
    end

    shared_examples "args" do
      it "generates args for user comment check" do
        expect(args_for(user).for_check).to include(expected_user_args)
      end

      it "generates args for user feedback" do
        expect(args_for(user).for_feedback).to include(expected_user_args)
      end

      it "generates args for post comment check" do
        expect(args_for(post).for_check).to include(expected_post_args)
      end

      it "generates args for post feedback" do
        expect(args_for(post).for_feedback).to include(expected_post_args)
      end
    end

    context "with akismet_transmit_email true" do
      before { SiteSetting.akismet_transmit_email = true }

      include_examples "args" do
        let(:expected_user_args) { user_args }
        let(:expected_post_args) { post_args }
      end
    end

    context "with akismet_transmit_email false" do
      before { SiteSetting.akismet_transmit_email = false }

      include_examples "args" do
        let(:expected_user_args) { user_args.except(:comment_author_email) }
        let(:expected_post_args) { post_args.except(:comment_author_email) }
      end
    end
  end
end
