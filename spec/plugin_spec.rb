# frozen_string_literal: true

require 'rails_helper'

describe "plugin" do
  before do
    SiteSetting.akismet_api_key = 'not_a_real_key'
    SiteSetting.akismet_enabled = true
  end

  it "queues posts on post for trust level 1" do
    user = Fabricate(:user, trust_level: TrustLevel[1])
    pc = PostCreator.new(user, raw: 'this is the new content for my topic', title: 'this is my new topic title')
    post = pc.create
    expect(DiscourseAkismet::PostsBouncer.to_check.length).to eq(1)
    expect(Jobs::CheckAkismetPost.jobs.length).to eq(0)
  end

  it "immediately queues posts on post for trust level 0" do
    user = Fabricate(:user, trust_level: TrustLevel[0])
    pc = PostCreator.new(user, raw: 'this is the new content for my topic', title: 'this is my new topic title')
    post = pc.create
    expect(DiscourseAkismet::PostsBouncer.to_check.length).to eq(1)
    expect(Jobs::CheckAkismetPost.jobs.length).to eq(1)
  end

end
