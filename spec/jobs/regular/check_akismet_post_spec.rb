# frozen_string_literal: true

require "rails_helper"

RSpec.describe Jobs::CheckAkismetPost do
  before { SiteSetting.akismet_enabled = true }

  describe "#execute" do
    subject(:execute) { described_class.new.execute(post_id: post.id) }

    let(:post) { Fabricate(:post) }

    it "does not create a reviewable when a reviewable queued post already exists for that target" do
      ReviewableQueuedPost.needs_review!(target: post, created_by: Discourse.system_user)

      execute

      expect(ReviewableAkismetPost.count).to be_zero
    end

    it "does not create a reviewable when a reviewable flagged post already exists for that target" do
      ReviewableFlaggedPost.needs_review!(target: post, created_by: Discourse.system_user)

      execute

      expect(ReviewableAkismetPost.count).to be_zero
    end

    shared_examples "confirmed ham posts" do
      it "does not create a reviewable for non-spam post" do
        execute

        expect(ReviewableAkismetPost.count).to be_zero
        expect(post.reload.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]).to eq(
          "confirmed_ham",
        )
      end
    end

    shared_examples "confirmed spam posts" do
      it "creates a reviewable for spam post" do
        execute

        expect(ReviewableAkismetPost.count).to eq(1)
        expect(post.reload.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]).to eq(
          "confirmed_spam",
        )
      end
    end

    context "with akismet" do
      before do
        SiteSetting.anti_spam_service = DiscourseAkismet::AntiSpamService::AKISMET
        SiteSetting.akismet_api_key = "fake_key"
        DiscourseAkismet::PostsBouncer.new.move_to_state(post, DiscourseAkismet::Bouncer::PENDING_STATE)
      end

      context "when client returns spam" do
        before { Akismet::Client.any_instance.stubs(:comment_check).returns("spam") }

        include_examples "confirmed spam posts"
      end

      context "when client returns ham" do
        before { Akismet::Client.any_instance.stubs(:comment_check).returns("ham") }

        include_examples "confirmed ham posts"
      end
    end

    context "with netease" do
      before do
        SiteSetting.anti_spam_service = DiscourseAkismet::AntiSpamService::NETEASE
        SiteSetting.netease_secret_id = "netease_id"
        SiteSetting.netease_secret_key = "netease_key"
        SiteSetting.netease_business_id = "business_id"
        DiscourseAkismet::PostsBouncer.new.move_to_state(post, DiscourseAkismet::Bouncer::PENDING_STATE)
      end

      context "when client returns spam" do
        before { Netease::Client.any_instance.stubs(:comment_check).returns("spam") }

        include_examples "confirmed spam posts"
      end

      context "when client returns ham" do
        before { Netease::Client.any_instance.stubs(:comment_check).returns("ham") }

        include_examples "confirmed ham posts"
      end
    end
  end
end
