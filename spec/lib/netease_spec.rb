# frozen_string_literal: true

describe Netease do
  fab!(:user) { Fabricate(:active_user) }
  fab!(:post) { Fabricate(:post) }
  let(:client) { Netease::Client.build_client }

  let(:post_args) { { dataId: "post-#{post.id}", content: "#{post.topic.title}\n\nHello world" } }

  let(:user_args) { { dataId: "user-#{user.id}", content: "This is my bio" } }

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
      expect(post.custom_fields["NETEASE_TASK_ID"]).to eq("fx6sxdcd89fvbvg4967b4787d78a")
    end

    it "returns 'spam' spam users" do
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

      expect(client.comment_check(user_args)).to eq("spam")
      expect(user.custom_fields["NETEASE_TASK_ID"]).to eq("fx6sxdcd89fvbvg4967b4787d78a")
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
      expect(post.custom_fields["NETEASE_TASK_ID"]).to eq("fx6sxdcd89fvbvg4967b4787d78a")
    end

    it "returns error details for error responses" do
      stub_request(:post, "http://as.dun.163.com/v5/text/check").to_return(
        status: 200,
        body: { code: 401, msg: "Invalid business Id" }.to_json,
      )

      expect(client.comment_check(post_args)).to eq(
        ["error", { code: "401", msg: "Invalid business Id", error: "Invalid business Id" }],
      )

      expect(post.custom_fields["NETEASE_TASK_ID"]).to be_nil
    end
  end

  describe "#submit_feedback" do
    let(:feedback_args) { { feedback: { taskId: "fx6sxdcd89fvbvg4967b4787d78a" } } }

    it "does not submit feedback if `taskId` is empty" do
      expect(client.submit_feedback("spam", { feedback: {} })).to eq(false)
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

        expect(client.submit_feedback(feedback, feedback_args)).to eq(true)
      end

      it "raises error for error response" do
        stub_request(:post, "http://as.dun.163.com/v2/text/feedback").to_return(
          status: 200,
          body: { code: 401, msg: "Invalid business ID", result: [] }.to_json,
        )

        expect { client.submit_feedback(feedback, feedback_args) }.to raise_error(
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

  describe "request args" do
    def args_for(target)
      Netease::RequestArgs.new(target)
    end

    it "generates args for user comment check" do
      expect(args_for(user).for_check).to include(
        dataId: "user-#{user.id}",
        content: user.user_profile&.bio_raw,
      )
    end

    it "generates args for user feedback" do
      user.upsert_custom_fields(NETEASE_TASK_ID: "fx6sxdcd89fvbvg4967b4787d78a")

      expect(args_for(user).for_feedback).to include(
        feedback: {
          taskId: "fx6sxdcd89fvbvg4967b4787d78a",
        },
      )
    end

    it "generates args for post comment check" do
      expect(args_for(post).for_check).to include(
        dataId: "post-#{post.id}",
        content: "#{post.topic.title}\n\nHello world",
      )
    end

    it "generates args for post feedback" do
      post.upsert_custom_fields(NETEASE_TASK_ID: "fx6sxdcd89fvbvg4967b4787d78a")

      expect(args_for(post).for_feedback).to include(
        feedback: {
          taskId: "fx6sxdcd89fvbvg4967b4787d78a",
        },
      )
    end
  end
end
