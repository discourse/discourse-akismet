# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DiscourseAkismet::UsersBouncer, if: defined?(Reviewable) do

  let(:user) do
    user = Fabricate(:user, trust_level: TrustLevel[0])
    user.user_profile.bio_raw = "I am batman"
    user
  end

  before { SiteSetting.akismet_review_users = true }

  describe "#should_check_user?" do

    it "returns false when setting is disabled" do
      SiteSetting.akismet_review_users = false

      expect(subject.should_check_user?(user)).to eq(false)
    end

    it "returns false when user is higher than TL0" do
      user.trust_level = TrustLevel[1]

      expect(subject.should_check_user?(user)).to eq(false)
    end

    it "returns false when user has no bio" do
      user.user_profile.bio_raw = ""

      expect(subject.should_check_user?(user)).to eq(false)
    end

    it "returns false if a Reviewable already exists for that user" do
      ReviewableUser.create_for(user)

      expect(subject.should_check_user?(user)).to eq(false)
    end

    it "returns true for TL0 with a bio" do
      expect(subject.should_check_user?(user)).to eq(true)
    end
  end

  describe "#enqueue_for_check" do
    it "enqueues a job when user is TL0 and bio is present" do
      expect {
        subject.enqueue_for_check(user)
      }.to change {
        Jobs::CheckUsersForSpam.jobs.size
      }.by(1)
    end
  end

  describe "#check_user" do
    it "does not create a Reviewable if Akismet says it's not spam" do
      expect {
        subject.check_user(akismet(is_spam: false), user)
      }.to_not change {
        ReviewableAkismetUser.count
      }
    end

    it "creates a Reviewable if Akismet says it's spam" do
      expect {
        subject.check_user(akismet(is_spam: true), user)
      }.to change {
        ReviewableAkismetUser.count
      }.by(1)

      reviewable = ReviewableAkismetUser.last
      expect(reviewable.target).to eq(user)
      expect(reviewable.created_by).to eq(Discourse.system_user)
      expect(reviewable.reviewable_by_moderator).to eq(true)
      expect(reviewable.payload['username']).to eq(user.username)
      expect(reviewable.payload['name']).to eq(user.name)
      expect(reviewable.payload['email']).to eq(user.email)
      expect(reviewable.payload['bio']).to eq(user.user_profile.bio_raw)

      score = ReviewableScore.last
      expect(score.user).to eq(Discourse.system_user)
      expect(score.reviewable_score_type).to eq(PostActionType.types[:spam])
      expect(score.take_action_bonus).to eq(0)
    end

    def akismet(is_spam:)
      mock("Akismet::Client").tap do |client|
        client.expects(:comment_check).returns(is_spam)
      end
    end
  end
end
