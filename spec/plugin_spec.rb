# frozen_string_literal: true

require "rails_helper"

describe Plugin::Instance do
  fab!(:user_tl0) { Fabricate(:user, trust_level: TrustLevel[0], refresh_auto_groups: true) }
  fab!(:user_tl1) { Fabricate(:user, trust_level: TrustLevel[1], refresh_auto_groups: true) }
  fab!(:admin) { Fabricate(:admin) }
  let(:post_params) do
    { raw: "this is the new content for my topic", title: "this is my new topic title" }
  end
  let(:user_tl0_post_creator) { PostCreator.new(user_tl0, post_params) }
  let(:user_tl1_post_creator) { PostCreator.new(user_tl1, post_params) }

  before do
    SiteSetting.akismet_api_key = "akismetkey"
    SiteSetting.akismet_enabled = true
  end

  it "marks post created by trust level 1 user for checking" do
    user_tl1_post_creator.create
    expect(DiscourseAkismet::PostsBouncer.to_check.length).to eq(1)
    expect(Jobs::CheckAkismetPost.jobs.length).to eq(0)
  end

  it "immediately queues post created by trust level 0 user for checking" do
    user_tl0_post_creator.create
    expect(DiscourseAkismet::PostsBouncer.to_check.length).to eq(1)
    expect(Jobs::CheckAkismetPost.jobs.length).to eq(1)
  end

  def expect_user_tl0_post_to_be_queued(post, state = "confirmed_ham")
    expect(DiscourseAkismet::PostsBouncer.to_check.length).to eq(1)
    expect(Jobs::CheckAkismetPost.jobs.length).to eq(1)

    # Short-circuit actual check and mark newly created post as ham
    post.upsert_custom_fields(DiscourseAkismet::Bouncer::AKISMET_STATE => state)
    Jobs::CheckAkismetPost.clear
  end

  it "does not queue edited post with no content changes" do
    post = user_tl0_post_creator.create
    expect_user_tl0_post_to_be_queued(post)

    category = Fabricate(:category)
    PostRevisor.new(post).revise!(post.user, category_id: category.id)
    expect(Jobs::CheckAkismetPost.jobs.length).to eq(0)

    expect(post.reload.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]).to eq(
      "confirmed_ham",
    )
  end

  it "queues topic title edits" do
    post = user_tl0_post_creator.create
    expect_user_tl0_post_to_be_queued(post)

    PostRevisor.new(post).revise!(post.user, title: post.topic.title + " revised")
    expect(DiscourseAkismet::PostsBouncer.to_check.length).to eq(1)
    expect(Jobs::CheckAkismetPost.jobs.length).to eq(1)

    expect(post.reload.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]).to eq(DiscourseAkismet::Bouncer::PENDING_STATE)
  end

  it "queues edited posts" do
    Jobs.run_immediately!

    post_creator =
      PostCreator.new(
        user_tl0,
        raw: "this is the new content for my topic",
        title: "this is my new topic title",
      )

    stub_request(:post, "https://akismetkey.rest.akismet.com/1.1/comment-check").to_return(
      { status: 200, body: "false" },
      { status: 200, body: "true" },
    )

    # Check original raw
    post = post_creator.create
    expect(post.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]).to eq(DiscourseAkismet::Bouncer::PENDING_STATE)
    expect(post.reload.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]).to eq(
      "confirmed_ham",
    )

    # Check edited raw
    PostRevisor.new(post).revise!(post.user, raw: post.raw + "spam")
    expect(post.reload.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]).to eq(
      "confirmed_spam",
    )
  end

  shared_examples "staff edited posts" do
    it "skips posts edited by a staff member" do
      Jobs.run_immediately!

      post_creator =
        PostCreator.new(
          user_tl0,
          raw: "this is the new content for my topic",
          title: "this is my new topic title",
        )

      # Check original raw
      post = post_creator.create
      expect(post.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]).to eq(DiscourseAkismet::Bouncer::PENDING_STATE)
      expect(post.reload.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]).to eq(
        "confirmed_ham",
      )

      # Check edited raw
      PostRevisor.new(post).revise!(admin, raw: post.raw + "more text by staff member")
      expect(post.reload.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]).to eq(
        "confirmed_ham",
      )
    end
  end

  shared_examples "recovered skipped posts" do
    it "queues recovered posts that were skipped" do
      post_creator =
        PostCreator.new(
          user_tl0,
          raw: "this is the new content for my topic",
          title: "this is my new topic title",
        )

      # Create the post and immediately destroy it, but leave the job running
      post = post_creator.create
      PostDestroyer.new(post.user, post).destroy
      DiscourseAkismet::PostsBouncer.new.perform_check(
        DiscourseAkismet::AntiSpamService.client,
        post.reload,
      )
      expect(post.reload.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]).to eq(DiscourseAkismet::Bouncer::SKIPPED_STATE)

      # Check the recovered post because it was not checked the first itme
      Jobs.run_immediately!
      PostDestroyer.new(post.user, post).recover
      expect(post.reload.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]).to eq(
        "confirmed_spam",
      )
    end
  end

  shared_examples "recovered checked posts" do
    it "does not queue recovered posts that were checked before" do
      Jobs.run_immediately!

      post_creator =
        PostCreator.new(
          user_tl0,
          raw: "this is the new content for my topic",
          title: "this is my new topic title",
        )

      # Check original raw
      post = post_creator.create
      expect(post.reload.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]).to eq(
        "confirmed_ham",
      )

      # Destroy and recover post to ensure the post is not checked again
      post.trash!
      PostDestroyer.new(post.user, post).recover
      expect(post.reload.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]).to eq(
        "confirmed_ham",
      )
    end
  end

  context "with akismet" do
    before do
      SiteSetting.anti_spam_service = DiscourseAkismet::AntiSpamService::AKISMET
      SiteSetting.akismet_api_key = "akismetkey"
    end

    context "when spam isn't detected" do
      before do
        stub_request(:post, "https://akismetkey.rest.akismet.com/1.1/comment-check").to_return(
          status: 200,
          body: "false",
        )
      end

      include_examples "recovered checked posts"
      include_examples "staff edited posts"
    end

    context "when spam is detected" do
      before do
        stub_request(:post, "https://akismetkey.rest.akismet.com/1.1/comment-check").to_return(
          status: 200,
          body: "true",
        )
      end

      include_examples "recovered skipped posts"
    end
  end

  context "with netease" do
    before do
      SiteSetting.anti_spam_service = DiscourseAkismet::AntiSpamService::NETEASE
      SiteSetting.netease_secret_id = "netease_id"
      SiteSetting.netease_secret_key = "netease_key"
      SiteSetting.netease_business_id = "business_id"
    end

    context "when spam isn't detected" do
      before do
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
      end

      include_examples "recovered checked posts"
      include_examples "staff edited posts"
    end

    context "when spam is detected" do
      before do
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

      include_examples "recovered skipped posts"
    end
  end

  context "with remaining reviewables" do
    let!(:user) { Fabricate(:user) }

    let!(:flagged_post) do
      Fabricate(:post, user: user).tap do |post|
        Fabricate(
          :reviewable_flagged_post,
          target: post,
          target_created_by: user,
          potential_spam: true,
        )
      end
    end

    let!(:akismet_post) do
      Fabricate(:post, user: user).tap do |post|
        DiscourseAkismet::PostsBouncer.new.send(:mark_as_spam, post)
      end
    end

    it "acts on all reviewables belonging to spammer" do
      ReviewableFlaggedPost.find_by(target: flagged_post).perform(Fabricate(:admin), :delete_user)
      expect(Jobs::UpdateAkismetStatus.jobs.count).to eq(2)
    end

    it "acts on all reviewables belonging to spammer" do
      ReviewableAkismetPost.find_by(target: akismet_post).perform(Fabricate(:admin), :delete_user)
      expect(Jobs::UpdateAkismetStatus.jobs.count).to eq(2)
    end

    it "works even if pending posts were trashed" do
      flagged_post.trash!
      expect {
        ReviewableAkismetPost.find_by(target: akismet_post).perform(Fabricate(:admin), :delete_user)
      }.not_to raise_error
      expect(Jobs::UpdateAkismetStatus.jobs.count).to eq(2)
    end
  end
end
