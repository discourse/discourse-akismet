# frozen_string_literal: true

require "rails_helper"
require_relative "../fabricators/reviewable_akismet_post_fabricator.rb"

describe DiscourseAkismet::PostsBouncer do
  subject(:bouncer) { described_class.new }

  before do
    SiteSetting.akismet_api_key = "akismetkey"
    SiteSetting.akismet_enabled = true

    @referrer = "https://discourse.org"
    @ip_address = "1.2.3.4"
    @user_agent = "Discourse Agent"

    bouncer.store_additional_information(
      post,
      { ip_address: @ip_address, user_agent: @user_agent, referrer: @referrer },
    )
  end

  let(:post) { Fabricate(:post) }

  describe "#args_for" do
    context "with akismet" do
      before { SiteSetting.anti_spam_service = DiscourseAkismet::AntiSpamService::AKISMET }

      it "returns args for a post" do
        result = bouncer.args_for(post, "check")
        expect(result[:content_type]).to eq("forum-post")
        expect(result[:permalink]).to be_present
        expect(result[:comment_content]).to be_present
        expect(result[:user_ip]).to eq(@ip_address)
        expect(result[:referrer]).to eq(@referrer)
        expect(result[:user_agent]).to eq(@user_agent)
        expect(result[:comment_author]).to eq(post.user.username)
        expect(result[:comment_author_email]).to eq(post.user.email)
        expect(result[:blog]).to eq(Discourse.base_url)
      end

      it "will omit email if the site setting is enabled" do
        SiteSetting.akismet_transmit_email = false
        result = bouncer.args_for(post, "check")
        expect(result[:comment_author_email]).to be_blank
      end

      it "works with deleted posts and topics" do
        topic_title = post.topic.title
        PostDestroyer.new(Discourse.system_user, post).destroy
        deleted_post = Post.with_deleted.find(post.id)

        result = bouncer.args_for(deleted_post, "check")

        expect(result[:comment_content]).to include(topic_title)
      end

      context "with custom munge" do
        after { described_class.reset_munge }

        before do
          described_class.munge_args do |args|
            args[:comment_author] = "CUSTOM: #{args[:comment_author]}"
            args.delete(:user_agent)
          end
        end

        it "will munge the args before returning them" do
          result = bouncer.args_for(post, "check")
          expect(result[:user_agent]).to be_blank
          expect(result[:comment_author]).to eq("CUSTOM: #{post.user.username}")

          described_class.reset_munge
          result = bouncer.args_for(post, "check")
          expect(result[:user_agent]).to eq("Discourse Agent")
          expect(result[:comment_author]).to eq(post.user.username)
        end
      end
    end

    context "with netease" do
      before do
        SiteSetting.anti_spam_service = DiscourseAkismet::AntiSpamService::NETEASE
        SiteSetting.netease_secret_id = "netease_id"
        SiteSetting.netease_secret_key = "netease_key"
        SiteSetting.netease_business_id = "business_id"
      end

      it "returns args for a post" do
        result = bouncer.args_for(post, "check")
        expect(result).to include(
          dataId: "post-#{post.id}",
          content: "#{post.topic.title}\n\nHello world",
        )
      end

      it "omits email if the site setting is enabled" do
        SiteSetting.akismet_transmit_email = false
        result = bouncer.args_for(post, "check")

        expect(result.values).not_to include(post.user.email)
      end

      it "returns args for deleted posts and topics" do
        topic_title = post.topic.title
        PostDestroyer.new(Discourse.system_user, post).destroy
        deleted_post = Post.with_deleted.find(post.id)

        result = bouncer.args_for(deleted_post, "check")

        expect(result[:content]).to include(topic_title)
      end

      context "with custom munge" do
        after { described_class.reset_munge }

        before do
          described_class.munge_args do |args|
            args[:dataId] = "#{Discourse.current_hostname}-#{args[:dataId]}"
          end
        end

        it "munges the args before returning them" do
          result = bouncer.args_for(post, "check")
          expect(result[:dataId]).to eq("#{Discourse.current_hostname}-post-#{post.id}")

          described_class.reset_munge
          result = bouncer.args_for(post, "check")
          expect(result[:dataId]).to eq("post-#{post.id}")
        end
      end
    end
  end

  describe "custom fields" do
    it "custom fields can be attached and IPs anonymized" do
      expect(post.custom_fields["AKISMET_IP_ADDRESS"]).to eq(@ip_address)
      expect(post.custom_fields["AKISMET_REFERRER"]).to eq(@referrer)
      expect(post.custom_fields["AKISMET_USER_AGENT"]).to eq(@user_agent)

      UserAnonymizer.new(post.user, nil, anonymize_ip: "0.0.0.0").make_anonymous
      post.reload
      expect(post.custom_fields["AKISMET_IP_ADDRESS"]).to eq("0.0.0.0")
    end

    describe "#clean_old_akismet_custom_fields" do
      before { bouncer.move_to_state(post, DiscourseAkismet::Bouncer::SKIPPED_STATE) }

      it "keeps recent Akismet custom fields" do
        post.upsert_custom_fields("NETEASE_TASK_ID" => "task_id_123")
        bouncer.clean_old_akismet_custom_fields

        post.reload

        expect(post.custom_fields.keys).to contain_exactly(*described_class::CUSTOM_FIELDS)
      end

      it "removes old Akismet custom fields" do
        PostCustomField.where(name: described_class::CUSTOM_FIELDS, post: post).update_all(
          created_at: 3.months.ago,
        )

        bouncer.clean_old_akismet_custom_fields

        post.reload
        expect(post.custom_fields.keys).to be_empty
      end
    end
  end

  describe "#check_post" do
    let(:client) { DiscourseAkismet::AntiSpamService.client }

    before { bouncer.move_to_state(post, DiscourseAkismet::Bouncer::PENDING_STATE) }

    shared_examples "successful post checks" do
      it "creates a new ReviewableAkismetPost when spam is confirmed by Akismet" do
        bouncer.perform_check(client, post)
        reviewable_akismet_post = ReviewableAkismetPost.last

        expect(reviewable_akismet_post).to be_pending
        expect(reviewable_akismet_post.post).to eq post
        expect(reviewable_akismet_post.reviewable_by_moderator).to eq true
        expect(reviewable_akismet_post.payload["post_cooked"]).to eq post.cooked

        # notifies user that post is hidden and includes post URL
        expect(Post.last.raw).to include(post.full_url)
        expect(Post.last.raw).to include(post.topic.title)
      end

      it "creates a new score for the new reviewable" do
        bouncer.perform_check(client, post)
        reviewable_akismet_score = ReviewableScore.last

        expect(reviewable_akismet_score.user).to eq Discourse.system_user
        expect(reviewable_akismet_score.reviewable_score_type).to eq PostActionType.types[:spam]
        expect(reviewable_akismet_score.take_action_bonus).to be_zero
      end

      it "publishes a message to display a banner on the topic page" do
        channel = [described_class::TOPIC_DELETED_CHANNEL, post.topic_id].join
        message = MessageBus.track_publish(channel) { bouncer.perform_check(client, post) }.first

        data = message.data

        expect(data).to eq("spam_found")
      end
    end

    context "with akismet success reponse" do
      before do
        SiteSetting.anti_spam_service = DiscourseAkismet::AntiSpamService::AKISMET
        stub_request(:post, "https://akismetkey.rest.akismet.com/1.1/comment-check").to_return(
          status: 200,
          body: "true",
        )
      end

      include_examples "successful post checks"
    end

    context "with neteaase success response" do
      before do
        SiteSetting.anti_spam_service = DiscourseAkismet::AntiSpamService::NETEASE
        SiteSetting.netease_secret_id = "netease_id"
        SiteSetting.netease_secret_key = "netease_key"
        SiteSetting.netease_business_id = "business_id"

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
      end

      include_examples "successful post checks"
    end

    context "with akismet API error" do
      before do
        stub_request(:post, "https://akismetkey.rest.akismet.com/1.1/comment-check").to_return(
          status: 200,
          body: "false",
          headers: {
            "X-akismet-error" => "status",
            "X-akismet-alert-code" => "123",
            "X-akismet-alert-msg" => "An alert message",
          },
        )
      end

      it "creates a new ReviewableAkismetPost when an API error is returned" do
        bouncer.move_to_state(post, DiscourseAkismet::Bouncer::PENDING_STATE)
        bouncer.perform_check(client, post)
        reviewable_akismet_post = ReviewableAkismetPost.last

        expect(reviewable_akismet_post).to be_pending
        expect(reviewable_akismet_post.post).to eq post
        expect(reviewable_akismet_post.reviewable_by_moderator).to eq true
        expect(reviewable_akismet_post.payload["external_error"]["error"]).to eq("status")
        expect(reviewable_akismet_post.payload["external_error"]["code"]).to eq("123")
        expect(reviewable_akismet_post.payload["external_error"]["msg"]).to eq("An alert message")
      end
    end

    context "with netease API error" do
      before do
        SiteSetting.anti_spam_service = DiscourseAkismet::AntiSpamService::NETEASE
        SiteSetting.netease_secret_id = "netease_id"
        SiteSetting.netease_secret_key = "netease_key"
        SiteSetting.netease_business_id = "business_id"

        stub_request(:post, "http://as.dun.163.com/v5/text/check").to_return(
          status: 200,
          body: { code: 400, msg: "Missing SecretId or businessId" }.to_json,
        )
      end

      it "creates a new ReviewableAkismetPost when an API error is returned" do
        bouncer.move_to_state(post, DiscourseAkismet::Bouncer::PENDING_STATE)
        bouncer.perform_check(client, post)
        reviewable_akismet_post = ReviewableAkismetPost.last

        expect(reviewable_akismet_post).to be_pending
        expect(reviewable_akismet_post.post).to eq post
        expect(reviewable_akismet_post.reviewable_by_moderator).to eq true
        expect(reviewable_akismet_post.payload["external_error"]["error"]).to eq(
          "Missing SecretId or businessId",
        )
        expect(reviewable_akismet_post.payload["external_error"]["code"]).to eq("400")
        expect(reviewable_akismet_post.payload["external_error"]["msg"]).to eq(
          "Missing SecretId or businessId",
        )
      end
    end
  end

  describe "#to_check" do
    it "retrieves posts waiting to be reviewed by Akismet" do
      bouncer.move_to_state(post, DiscourseAkismet::Bouncer::PENDING_STATE)

      posts_to_check = described_class.to_check

      expect(posts_to_check).to contain_exactly(post)
    end

    it "does not retrieve posts that already had another reviewable queued post" do
      bouncer.move_to_state(post, DiscourseAkismet::Bouncer::PENDING_STATE)
      ReviewableQueuedPost.needs_review!(target: post, created_by: Discourse.system_user)

      expect(described_class.to_check).to be_empty
    end

    it "does not retrieve posts that already had another reviewable flagged post" do
      bouncer.move_to_state(post, DiscourseAkismet::Bouncer::PENDING_STATE)
      ReviewableFlaggedPost.needs_review!(target: post, created_by: Discourse.system_user)

      expect(described_class.to_check).to be_empty
    end
  end

  describe "#should_check?" do
    fab!(:user) { Fabricate(:user, refresh_auto_groups: true, trust_level: TrustLevel[1]) }
    fab!(:post) { Fabricate(:post, raw: "More than 20 characters long", user: user) }

    before do
      SiteSetting.skip_akismet_groups = Group::AUTO_GROUPS[:trust_level_2]
      post.user.post_count
      post.user.user_stat.update!(post_count: 2)
    end

    it { expect(bouncer.should_check?(nil)).to eq(false) }

    it "returns false the topic was deleted" do
      post.topic.trash!

      expect(bouncer.should_check?(post.reload)).to eq(false)
    end

    it "returns false when the topic is a private message" do
      post.topic.archetype = Archetype.private_message

      expect(bouncer.should_check?(post)).to eq(false)
    end

    it "returns false the the post body is less than 20 chars long" do
      post.raw = "Less than 20 chars"

      expect(bouncer.should_check?(post)).to eq(false)
    end

    it "returns false when users with 19+ posts are skipped" do
      post.user.user_stat.update!(post_count: 20)
      SiteSetting.skip_akismet_posts = 19

      expect(bouncer.should_check?(post)).to eq(false)
    end

    it "returns false when post content is just an URI" do
      post.user.user_stat.update!(post_count: 2)
      post.raw = "https://testurl.test/test/akismet/96850311111131"

      expect(bouncer.should_check?(post)).to eq(false)
    end

    it "returns false when the plugin is disabled" do
      SiteSetting.akismet_enabled = false

      expect(bouncer.should_check?(post)).to eq(false)
    end

    it "returns false when a reviewable already exists" do
      Fabricate(:reviewable_akismet_post, target: post)

      expect(bouncer.should_check?(post)).to eq(false)
    end

    it "returns true when the user doesn't have the correct trust level" do
      SiteSetting.skip_akismet_groups = Group::AUTO_GROUPS[:trust_level_4]
      expect(bouncer.should_check?(post)).to eq(true)
    end

    it "returns false when the user has the correct trust level" do
      SiteSetting.skip_akismet_groups = Group::AUTO_GROUPS[:trust_level_1]
      expect(bouncer.should_check?(post)).to eq(false)
    end

    describe "for review_tl1_users_first_post setting" do
      before do
        SiteSetting.review_tl1_users_first_post = true
        post.user.user_stat.update!(post_count: 0)
      end

      it "returns true on the first post of a TL1 user" do
        expect(bouncer.should_check?(post)).to eq(true)
      end

      it "returns false for a TL1 user's first post when the setting is disabled" do
        SiteSetting.skip_akismet_groups = Group::AUTO_GROUPS[:trust_level_1]
        SiteSetting.review_tl1_users_first_post = false
        expect(bouncer.should_check?(post)).to eq(false)
      end

      it "returns false when TL0+ users are skipped" do
        post.user.user_stat.update!(post_count: 2)
        SiteSetting.skip_akismet_groups = Group::AUTO_GROUPS[:trust_level_0]

        expect(bouncer.should_check?(post)).to eq(false)
      end
    end
  end
end
