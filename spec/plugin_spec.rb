# frozen_string_literal: true

require 'rails_helper'

describe 'plugin' do
  fab!(:user_tl0) { Fabricate(:user, trust_level: TrustLevel[0]) }
  fab!(:user_tl1) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:admin) { Fabricate(:admin) }

  before do
    SiteSetting.akismet_api_key = 'akismetkey'
    SiteSetting.akismet_enabled = true
  end

  it 'queues posts on post for trust level 1' do
    post_creator = PostCreator.new(user_tl1, raw: 'this is the new content for my topic', title: 'this is my new topic title')
    post = post_creator.create
    expect(DiscourseAkismet::PostsBouncer.to_check.length).to eq(1)
    expect(Jobs::CheckAkismetPost.jobs.length).to eq(0)
  end

  it 'immediately queues posts on post for trust level 0' do
    post_creator = PostCreator.new(user_tl0, raw: 'this is the new content for my topic', title: 'this is my new topic title')
    post = post_creator.create
    expect(DiscourseAkismet::PostsBouncer.to_check.length).to eq(1)
    expect(Jobs::CheckAkismetPost.jobs.length).to eq(1)
  end

  it 'queues edited posts' do
    Jobs.run_immediately!

    post_creator = PostCreator.new(user_tl0, raw: 'this is the new content for my topic', title: 'this is my new topic title')

    stub_request(:post, 'https://akismetkey.rest.akismet.com/1.1/comment-check')
      .to_return({ status: 200, body: 'false' }, { status: 200, body: 'true' })

    # Check original raw
    post = post_creator.create
    expect(post.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]).to eq('pending')
    expect(post.reload.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]).to eq('confirmed_ham')

    # Check edited raw
    PostRevisor.new(post).revise!(post.user, raw: post.raw + 'spam')
    expect(post.reload.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]).to eq('confirmed_spam')
  end

  it 'skips posts edited by a staff member' do
    Jobs.run_immediately!

    post_creator = PostCreator.new(user_tl0, raw: 'this is the new content for my topic', title: 'this is my new topic title')

    stub_request(:post, 'https://akismetkey.rest.akismet.com/1.1/comment-check')
      .to_return({ status: 200, body: 'false' }, { status: 200, body: 'true' })

    # Check original raw
    post = post_creator.create
    expect(post.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]).to eq('pending')
    expect(post.reload.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]).to eq('confirmed_ham')

    # Check edited raw
    PostRevisor.new(post).revise!(admin, raw: post.raw + 'more text by staff member')
    expect(post.reload.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]).to eq('confirmed_ham')
  end

  it 'queues recovered posts that were skipped' do
    post_creator = PostCreator.new(user_tl0, raw: 'this is the new content for my topic', title: 'this is my new topic title')

    # Create the post and immediately destroy it, but leave the job running
    post = post_creator.create
    PostDestroyer.new(post.user, post).destroy
    DiscourseAkismet::PostsBouncer.new.perform_check(Akismet::Client.build_client, post.reload)
    expect(post.reload.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]).to eq('skipped')

    # Check the recovered post because it was not checked the first itme
    Jobs.run_immediately!
    stub_request(:post, 'https://akismetkey.rest.akismet.com/1.1/comment-check').to_return(status: 200, body: 'true')
    PostDestroyer.new(post.user, post).recover
    expect(post.reload.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]).to eq('confirmed_spam')
  end

  it 'does not queue recovered posts that were checked before' do
    Jobs.run_immediately!

    post_creator = PostCreator.new(user_tl0, raw: 'this is the new content for my topic', title: 'this is my new topic title')

    stub_request(:post, 'https://akismetkey.rest.akismet.com/1.1/comment-check')
      .to_return({ status: 200, body: 'false' }, { status: 200, body: 'true' })

    # Check original raw
    post = post_creator.create
    expect(post.reload.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]).to eq('confirmed_ham')

    # Destroy and recover post to ensure the post is not checked again
    post.trash!
    PostDestroyer.new(post.user, post).recover
    expect(post.reload.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]).to eq('confirmed_ham')
  end

  context "acts on remaining reviewables" do
    let!(:user) { Fabricate(:user) }

    let!(:flagged_post) do
      Fabricate(:post, user: user).tap do |post|
        Fabricate(
          :reviewable_flagged_post,
          target: post,
          target_created_by: user,
          potential_spam: true
        )
      end
    end

    let!(:akismet_post) do
      Fabricate(:post, user: user).tap do |post|
        DiscourseAkismet::PostsBouncer.new.send(:mark_as_spam, post)
      end
    end

    it 'acts on all reviewables belonging to spammer' do
      ReviewableFlaggedPost.find_by(target: flagged_post).perform(Fabricate(:admin), :delete_user)
      expect(Jobs::UpdateAkismetStatus.jobs.count).to eq(2)
    end

    it 'acts on all reviewables belonging to spammer' do
      ReviewableAkismetPost.find_by(target: akismet_post).perform(Fabricate(:admin), :delete_user)
      expect(Jobs::UpdateAkismetStatus.jobs.count).to eq(2)
    end

    it 'works even if pending posts were trashed' do
      flagged_post.trash!
      expect { ReviewableAkismetPost.find_by(target: akismet_post).perform(Fabricate(:admin), :delete_user) }
        .not_to raise_error
      expect(Jobs::UpdateAkismetStatus.jobs.count).to eq(2)
    end
  end
end
