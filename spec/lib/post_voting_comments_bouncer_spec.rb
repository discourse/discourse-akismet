# frozen_string_literal: true

require_relative "../fabricators/reviewable_akismet_post_fabricator.rb"

describe DiscourseAkismet::PostVotingCommentsBouncer do
  subject(:bouncer) { described_class.new }

  before do
    SiteSetting.akismet_api_key = "akismetkey"
    SiteSetting.akismet_enabled = true

    @referrer = "https://discourse.org"
    @ip_address = "1.2.3.4"
    @user_agent = "Discourse Agent"

    bouncer.store_additional_information(
      comment,
      { ip_address: @ip_address, user_agent: @user_agent, referrer: @referrer },
    )
  end

  fab!(:topic) { Fabricate(:topic, subtype: Topic::POST_VOTING_SUBTYPE) }
  fab!(:post) { Fabricate(:post, topic: topic) }
  fab!(:comment) { Fabricate(:post_voting_comment, post: post) }

  describe "#args_for" do
    context "with akismet" do
      before { SiteSetting.anti_spam_service = DiscourseAkismet::AntiSpamService::AKISMET }

      it "returns args for a post voting comment" do
        result = bouncer.args_for(comment, "check")
        expect(result[:content_type]).to eq("post-voting-comment")
        expect(result[:permalink]).to be_present
        expect(result[:comment_content]).to be_present
        expect(result[:user_ip]).to eq(@ip_address)
        expect(result[:referrer]).to eq(@referrer)
        expect(result[:user_agent]).to eq(@user_agent)
        expect(result[:comment_author]).to eq(comment.user.username)
        expect(result[:comment_author_email]).to eq(comment.user.email)
        expect(result[:blog]).to eq(Discourse.base_url)
      end

      it "will omit email if the site setting is enabled" do
        SiteSetting.akismet_transmit_email = false
        result = bouncer.args_for(comment, "check")
        expect(result[:comment_author_email]).to be_blank
      end

      it "works with deleted posts voting comments and posts" do
        comment.trash!
        deleted_comment = PostVotingComment.unscoped.find(comment.id)
        result = bouncer.args_for(deleted_comment, "check")

        expect(result[:comment_content]).to include(comment.post.raw)
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
          result = bouncer.args_for(comment, "check")
          expect(result[:user_agent]).to be_blank
          expect(result[:comment_author]).to eq("CUSTOM: #{comment.user.username}")

          described_class.reset_munge
          result = bouncer.args_for(comment, "check")
          expect(result[:user_agent]).to eq("Discourse Agent")
          expect(result[:comment_author]).to eq(comment.user.username)
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

      it "returns args for a post voting comment" do
        result = bouncer.args_for(comment, "check")
        expect(result).to include(
          dataId: "post-voting-comment-#{comment.id}",
          content: "#{comment.post.raw}\n\nHello world",
        )
      end

      it "omits email if the site setting is enabled" do
        SiteSetting.akismet_transmit_email = false
        result = bouncer.args_for(comment, "check")

        expect(result.values).not_to include(comment.user.email)
      end

      it "returns args for deleted posts voting comments" do
        comment.trash!
        deleted_comment = PostVotingComment.unscoped.find(comment.id)

        result = bouncer.args_for(deleted_comment, "check")

        expect(result[:content]).to include(comment.post.raw)
      end

      context "with custom munge" do
        after { described_class.reset_munge }

        before do
          described_class.munge_args do |args|
            args[:dataId] = "#{Discourse.current_hostname}-#{args[:dataId]}"
          end
        end

        it "munges the args before returning them" do
          result = bouncer.args_for(comment, "check")
          expect(result[:dataId]).to eq(
            "#{Discourse.current_hostname}-post-voting-comment-#{comment.id}",
          )

          described_class.reset_munge
          result = bouncer.args_for(comment, "check")
          expect(result[:dataId]).to eq("post-voting-comment-#{comment.id}")
        end
      end
    end
  end

  describe "custom fields" do
    it "custom fields can be attached and IPs anonymized" do
      expect(comment.custom_fields["AKISMET_IP_ADDRESS"]).to eq(@ip_address)
      expect(comment.custom_fields["AKISMET_REFERRER"]).to eq(@referrer)
      expect(comment.custom_fields["AKISMET_USER_AGENT"]).to eq(@user_agent)
      UserAnonymizer.new(comment.user, nil, anonymize_ip: "0.0.0.0").make_anonymous
      comment.reload
      expect(comment.custom_fields["AKISMET_IP_ADDRESS"]).to eq("0.0.0.0")
    end

    describe "#clean_old_akismet_custom_fields" do
      before { bouncer.move_to_state(comment, DiscourseAkismet::Bouncer::SKIPPED_STATE) }

      it "keeps recent Akismet custom fields" do
        comment.upsert_custom_fields("NETEASE_TASK_ID" => "task_id_123")
        bouncer.clean_old_akismet_custom_fields

        comment.reload

        expect(comment.custom_fields.keys).to contain_exactly(*described_class::CUSTOM_FIELDS)
      end

      it "removes old Akismet custom fields" do
        PostVotingCommentCustomField.where(
          name: described_class::CUSTOM_FIELDS,
          post_voting_comment: comment,
        ).update_all(created_at: 3.months.ago)

        bouncer.clean_old_akismet_custom_fields

        comment.reload
        expect(comment.custom_fields.keys).to be_empty
      end
    end
  end

  describe "#check_post_voting_comment" do
    let(:client) { DiscourseAkismet::AntiSpamService.client }

    before { bouncer.move_to_state(comment, DiscourseAkismet::Bouncer::PENDING_STATE) }

    shared_examples "successful post voting comment checks" do
      it "creates a new ReviewableAkismetPostVotingComment when spam is confirmed by Akismet" do
        bouncer.perform_check(client, comment)

        reviewable_akismet_post_voting_comment = ReviewableAkismetPostVotingComment.last

        expect(reviewable_akismet_post_voting_comment).to be_pending
        expect(reviewable_akismet_post_voting_comment.comment).to eq comment
        expect(reviewable_akismet_post_voting_comment.reviewable_by_moderator).to eq true
        expect(
          reviewable_akismet_post_voting_comment.payload["comment_cooked"],
        ).to eq comment.cooked
      end

      it "creates a new score for the new reviewable" do
        bouncer.perform_check(client, comment)
        reviewable_akismet_score = ReviewableScore.last

        expect(reviewable_akismet_score.user).to eq Discourse.system_user
        expect(reviewable_akismet_score.reviewable_score_type).to eq PostActionType.types[:spam]
        expect(reviewable_akismet_score.take_action_bonus).to be_zero
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

      include_examples "successful post voting comment checks"
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

      include_examples "successful post voting comment checks"
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

      it "creates a new ReviewableAkismetPostVotingComment when an API error is returned" do
        bouncer.move_to_state(comment, DiscourseAkismet::Bouncer::PENDING_STATE)
        bouncer.perform_check(client, comment)
        reviewable_akismet_post_voting_comment = ReviewableAkismetPostVotingComment.last

        expect(reviewable_akismet_post_voting_comment).to be_pending
        expect(reviewable_akismet_post_voting_comment.comment).to eq comment
        expect(reviewable_akismet_post_voting_comment.reviewable_by_moderator).to eq true
        expect(reviewable_akismet_post_voting_comment.payload["external_error"]["error"]).to eq(
          "status",
        )
        expect(reviewable_akismet_post_voting_comment.payload["external_error"]["code"]).to eq(
          "123",
        )
        expect(reviewable_akismet_post_voting_comment.payload["external_error"]["msg"]).to eq(
          "An alert message",
        )
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

      it "creates a new ReviewableAkismetPostVotingComment when an API error is returned" do
        bouncer.move_to_state(comment, DiscourseAkismet::Bouncer::PENDING_STATE)
        bouncer.perform_check(client, comment)
        reviewable_akismet_post_voting_comment = ReviewableAkismetPostVotingComment.last

        expect(reviewable_akismet_post_voting_comment).to be_pending
        expect(reviewable_akismet_post_voting_comment.comment).to eq comment
        expect(reviewable_akismet_post_voting_comment.reviewable_by_moderator).to eq true
        expect(reviewable_akismet_post_voting_comment.payload["external_error"]["error"]).to eq(
          "Missing SecretId or businessId",
        )
        expect(reviewable_akismet_post_voting_comment.payload["external_error"]["code"]).to eq(
          "400",
        )
        expect(reviewable_akismet_post_voting_comment.payload["external_error"]["msg"]).to eq(
          "Missing SecretId or businessId",
        )
      end
    end
  end

  describe "#to_check" do
    it "retrieves post voting comments waiting to be reviewed by Akismet" do
      bouncer.move_to_state(comment, DiscourseAkismet::Bouncer::PENDING_STATE)

      post_voting_comments_to_check = described_class.to_check

      expect(post_voting_comments_to_check).to contain_exactly(comment)
    end

    it "does not retrieve post voting comments that already had another reviewable flagged post voting comment" do
      bouncer.move_to_state(comment, DiscourseAkismet::Bouncer::PENDING_STATE)
      ReviewablePostVotingComment.needs_review!(target: comment, created_by: Discourse.system_user)
      expect(described_class.to_check).to be_empty
    end
  end

  describe "#should_check?" do
    let(:user) { comment.user }

    it { expect(bouncer.should_check?(nil)).to eq(false) }

    before do
      SiteSetting.skip_akismet_trust_level = TrustLevel[2]

      user.user_stat # Create user stat object

      post.raw = "More than 20 characters long"
      comment.raw = "More than 500 characters long"
      user.trust_level = TrustLevel[1]
    end

    it "returns true on the first post of a TL1 user" do
      SiteSetting.skip_akismet_trust_level = TrustLevel[1]

      expect(bouncer.should_check?(comment)).to eq(true)
    end

    it "returns false for a TL1 user's first post when the setting is disabled" do
      SiteSetting.review_tl1_users_first_post_voting_comment = false
      SiteSetting.skip_akismet_trust_level = TrustLevel[1]

      expect(bouncer.should_check?(comment)).to eq(false)
    end

    it "returns false the topic was deleted" do
      comment.post.topic.trash!
      expect(bouncer.should_check?(comment.reload)).to eq(false)
    end

    it "returns false the post voting comment body is less than 20 chars long" do
      comment.raw = "Less than 20 chars"

      expect(bouncer.should_check?(comment)).to eq(false)
    end

    it "returns false when TL0+ users are skipped" do
      user.user_stat.post_count = 2
      SiteSetting.skip_akismet_trust_level = TrustLevel[0]

      expect(bouncer.should_check?(comment)).to eq(false)
    end

    it "returns false when post voting comment content is just an URI" do
      user.user_stat.post_count = 2
      comment.raw = "https://testurl.test/test/akismet/96850311111131"

      expect(bouncer.should_check?(comment)).to eq(false)
    end

    it "returns false when the plugin is disabled" do
      SiteSetting.akismet_enabled = false

      expect(bouncer.should_check?(comment)).to eq(false)
    end

    it "returns false when a reviewable already exists" do
      Fabricate(:reviewable_akismet_post_voting_comment, target: comment)

      expect(bouncer.should_check?(comment)).to eq(false)
    end
  end
end
