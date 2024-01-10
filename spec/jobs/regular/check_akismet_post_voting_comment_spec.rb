# frozen_string_literal: true

require "rails_helper"

RSpec.describe Jobs::CheckAkismetPostVotingComment do
  fab!(:topic) { Fabricate(:topic, subtype: Topic::POST_VOTING_SUBTYPE) }
  fab!(:post) { Fabricate(:post, topic: topic) }
  fab!(:post_voting_comment) { Fabricate(:post_voting_comment, post: post) }

  before { SiteSetting.akismet_enabled = true }
  describe "#execute" do
    subject(:check_akismet_post_voting_comment) { described_class.new }

    it "does not create a reviewable when a reviewable flagged post already exists for that target" do
      ReviewablePostVotingComment.needs_review!(
        target: post_voting_comment,
        created_by: Discourse.system_user,
      )

      check_akismet_post_voting_comment.execute(comment_id: post_voting_comment.id)

      expect(ReviewableAkismetPostVotingComment.count).to be_zero
    end

    shared_examples "confirmed ham post voting comments" do
      it "does not create a reviewable for non-spam post" do
        check_akismet_post_voting_comment.execute(comment_id: post_voting_comment.id)

        expect(ReviewableAkismetPostVotingComment.count).to be_zero
        expect(
          post_voting_comment.reload.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE],
        ).to eq("confirmed_ham")
      end
    end

    shared_examples "confirmed spam post voting comments" do
      it "creates a reviewable for spam post" do
        check_akismet_post_voting_comment.execute(comment_id: post_voting_comment.id)

        expect(ReviewableAkismetPostVotingComment.count).to eq(1)
        expect(
          post_voting_comment.reload.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE],
        ).to eq("confirmed_spam")
      end
    end

    context "with akismet" do
      before do
        SiteSetting.anti_spam_service = DiscourseAkismet::AntiSpamService::AKISMET
        SiteSetting.akismet_api_key = "fake_key"
        DiscourseAkismet::PostVotingCommentsBouncer.new.move_to_state(
          post_voting_comment,
          "pending",
        )
      end

      context "when client returns spam" do
        before { Akismet::Client.any_instance.stubs(:comment_check).returns("spam") }

        include_examples "confirmed spam post voting comments"
      end

      context "when client returns ham" do
        before { Akismet::Client.any_instance.stubs(:comment_check).returns("ham") }

        include_examples "confirmed ham post voting comments"
      end
    end

    context "with netease" do
      before do
        SiteSetting.anti_spam_service = DiscourseAkismet::AntiSpamService::NETEASE
        SiteSetting.netease_secret_id = "netease_id"
        SiteSetting.netease_secret_key = "netease_key"
        SiteSetting.netease_business_id = "business_id"
        DiscourseAkismet::PostVotingCommentsBouncer.new.move_to_state(
          post_voting_comment,
          "pending",
        )
      end

      context "when client returns spam" do
        before { Netease::Client.any_instance.stubs(:comment_check).returns("spam") }

        include_examples "confirmed spam post voting comments"
      end

      context "when client returns ham" do
        before { Netease::Client.any_instance.stubs(:comment_check).returns("ham") }

        include_examples "confirmed ham post voting comments"
      end
    end
  end
end
