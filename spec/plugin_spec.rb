# frozen_string_literal: true

require 'rails_helper'

describe 'plugin' do
  fab!(:user_tl0) { Fabricate(:user, trust_level: TrustLevel[0]) }
  fab!(:user_tl1) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:admin) { Fabricate(:admin) }

  before do
    SiteSetting.akismet_api_key = 'not_a_real_key'
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

    # Check original raw
    stub_request(:post, 'https://not_a_real_key.rest.akismet.com/1.1/comment-check').to_return(status: 200, body: 'false', headers: {})
    post = post_creator.create
    expect(post.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]).to eq('new')
    expect(post.reload.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]).to eq('confirmed_ham')

    # Check edited raw
    stub_request(:post, 'https://not_a_real_key.rest.akismet.com/1.1/comment-check').to_return(status: 200, body: 'true', headers: {})
    PostRevisor.new(post).revise!(post.user, raw: post.raw + ' akismet-guaranteed-spam')
    expect(post.reload.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]).to eq('confirmed_spam')
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
    stub_request(:post, 'https://not_a_real_key.rest.akismet.com/1.1/comment-check').to_return(status: 200, body: 'true', headers: {})
    PostDestroyer.new(post.user, post).recover
    expect(post.reload.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]).to eq('confirmed_spam')
  end

  it 'does not queue recovered posts that were checked before' do
    Jobs.run_immediately!

    post_creator = PostCreator.new(user_tl0, raw: 'this is the new content for my topic', title: 'this is my new topic title')

    # Check original raw
    stub_request(:post, 'https://not_a_real_key.rest.akismet.com/1.1/comment-check').to_return(status: 200, body: 'false', headers: {})
    post = post_creator.create
    expect(post.reload.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]).to eq('confirmed_ham')

    # Destroy and recover post to ensure the post is not checked again
    stub_request(:post, 'https://not_a_real_key.rest.akismet.com/1.1/comment-check').to_return(status: 200, body: 'true', headers: {})
    post.trash!
    PostDestroyer.new(post.user, post).recover
    expect(post.reload.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]).to eq('confirmed_ham')
  end

  it 'submits feedback on all posts a spammer posted' do
    reviewable = Fabricate(:reviewable)
    reviewable.reviewable_scores.build(
      user: admin,
      reviewable_score_type: 0,
      status: ReviewableScore.statuses[:pending],
      reason: 'suspect_user'
    )

    Fabricate(:post, user: reviewable.target)
    Fabricate(:post, user: reviewable.target)

    reviewable.perform(admin, :delete_user)

    expect(Jobs::UpdateAkismetStatus.jobs.length).to eq(3) # 1 for the user and 2 more for each user's posts
  end
end
