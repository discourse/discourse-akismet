# frozen_string_literal: true

RSpec.describe DiscourseAkismet::UsersBouncer do
  subject(:bouncer) { described_class.new }

  let(:user) do
    Fabricate(:user, trust_level: TrustLevel[0]).tap do |user|
      user.user_profile.bio_raw = "I am batman"
      user.user_auth_token_logs = [
        UserAuthTokenLog.new(client_ip: "127.0.0.1", action: "an_action"),
      ]
    end
  end

  before do
    SiteSetting.akismet_enabled = true
    SiteSetting.akismet_review_users = true
    SiteSetting.akismet_api_key = "fake_key"
  end

  describe "#args_for" do
    context "with akismet" do
      before { SiteSetting.anti_spam_service = DiscourseAkismet::AntiSpamService::AKISMET }

      it "returns args for a user" do
        profile = user.user_profile
        token = user.user_auth_token_logs.last

        result = bouncer.args_for(user, "check")
        expect(result[:content_type]).to eq("signup")
        expect(result[:permalink]).to eq("#{Discourse.base_url}/u/#{user.username_lower}")
        expect(result[:comment_author]).to eq(user.username)
        expect(result[:comment_content]).to eq(profile.bio_raw)
        expect(result[:comment_author_url]).to eq(profile.website)
        expect(result[:user_ip]).to eq(token.client_ip.to_s)
        expect(result[:user_agent]).to eq(token.user_agent)
        expect(result[:blog]).to eq(Discourse.base_url)
      end
    end

    context "with netease" do
      before do
        SiteSetting.anti_spam_service = DiscourseAkismet::AntiSpamService::NETEASE
        SiteSetting.netease_secret_id = "netease_id"
        SiteSetting.netease_secret_key = "netease_key"
        SiteSetting.netease_business_id = "business_id"
      end

      it "returns args for a user" do
        profile = user.user_profile
        token = user.user_auth_token_logs.last

        result = bouncer.args_for(user, "check")

        expect(result).to include(dataId: "user-#{user.id}", content: user.user_profile&.bio_raw)
      end
    end
  end

  describe "#should_check?" do
    it "returns false when setting is disabled" do
      SiteSetting.akismet_review_users = false

      expect(bouncer.should_check?(user)).to eq(false)
    end

    it "returns false when user is higher than TL0" do
      user.trust_level = TrustLevel[1]

      expect(bouncer.should_check?(user)).to eq(false)
    end

    it "returns false when user has no bio" do
      user.user_profile.bio_raw = ""

      expect(bouncer.should_check?(user)).to eq(false)
    end

    it "returns false if a Reviewable already exists for that user" do
      ReviewableUser.create_for(user)

      expect(bouncer.should_check?(user)).to eq(false)
    end

    it "returns true for TL0 with a bio" do
      expect(bouncer.should_check?(user)).to eq(true)
    end

    it "returns false when there are no auth token logs for that user" do
      user.user_auth_token_logs = []

      expect(bouncer.should_check?(user)).to eq(false)
    end

    it "returns false when there client ip is not present" do
      user.user_auth_token_logs = [UserAuthTokenLog.new(client_ip: nil, action: "an_action")]

      expect(bouncer.should_check?(user)).to eq(false)
    end
  end

  describe "#enqueue_for_check" do
    it "enqueues a job when user is TL0 and bio is present" do
      expect { bouncer.enqueue_for_check(user) }.to change { Jobs::CheckAkismetUser.jobs.size }.by(
        1,
      )
    end
  end

  describe "#check_user" do
    def anti_spam_service(client_name:, is_spam:)
      mock(client_name).tap do |client|
        client.expects(:comment_check).returns(is_spam ? "spam" : "ham")
      end
    end

    def anti_spam_service_error(client_name:)
      mock(client_name).tap do |client|
        client.expects(:comment_check).returns(
          ["error", { "error" => "status", "code" => "123", "msg" => "An alert message" }],
        )
      end
    end

    shared_examples "reviewables" do
      it "does not create a Reviewable if anti-spam service says it's not spam" do
        expect {
          bouncer.perform_check(anti_spam_service(client_name: client_name, is_spam: false), user)
        }.to_not change { ReviewableAkismetUser.count }
      end

      it "creates a Reviewable if anti-spam service says it's spam" do
        expect {
          bouncer.perform_check(anti_spam_service(client_name: client_name, is_spam: true), user)
        }.to change { ReviewableAkismetUser.count }.by(1)

        reviewable = ReviewableAkismetUser.last
        expect(reviewable.target).to eq(user)
        expect(reviewable.created_by).to eq(Discourse.system_user)
        expect(reviewable.reviewable_by_moderator).to eq(true)
        expect(reviewable.payload["username"]).to eq(user.username)
        expect(reviewable.payload["name"]).to eq(user.name)
        expect(reviewable.payload["email"]).to eq(user.email)
        expect(reviewable.payload["bio"]).to eq(user.user_profile.bio_raw)

        score = ReviewableScore.last
        expect(score.user).to eq(Discourse.system_user)
        expect(score.reviewable_score_type).to eq(PostActionType.types[:spam])
        expect(score.take_action_bonus).to eq(0)
      end

      it "creates a Reviewable if anti-spam service returns an API error" do
        expect {
          bouncer.perform_check(anti_spam_service_error(client_name: client_name), user)
        }.to change { ReviewableAkismetUser.count }.by(1)

        reviewable = ReviewableAkismetUser.last
        expect(reviewable.target).to eq(user)
        expect(reviewable.created_by).to eq(Discourse.system_user)
        expect(reviewable.reviewable_by_moderator).to eq(true)
        expect(reviewable.payload["username"]).to eq(user.username)
        expect(reviewable.payload["name"]).to eq(user.name)
        expect(reviewable.payload["email"]).to eq(user.email)
        expect(reviewable.payload["bio"]).to eq(user.user_profile.bio_raw)

        score = ReviewableScore.last
        expect(score.user).to eq(Discourse.system_user)
      end
    end

    context "with akismet" do
      let(:client_name) { "Akismet::Client" }

      before { SiteSetting.anti_spam_service = DiscourseAkismet::AntiSpamService::AKISMET }

      include_examples "reviewables"
    end

    context "with netease" do
      let(:client_name) { "Netease::Client" }
      before do
        SiteSetting.anti_spam_service = DiscourseAkismet::AntiSpamService::NETEASE
        SiteSetting.netease_secret_id = "netease_id"
        SiteSetting.netease_secret_key = "netease_key"
        SiteSetting.netease_business_id = "business_id"
      end

      include_examples "reviewables"
    end
  end

  describe ".to_check" do
    it "returns users in new state and ignore the rest" do
      user_to_check = Fabricate(:user, trust_level: 0)
      user_to_ignore = Fabricate(:user, trust_level: 0)
      bouncer.move_to_state(user_to_check, DiscourseAkismet::Bouncer::PENDING_STATE)
      bouncer.move_to_state(user_to_ignore, "confirmed_ham")

      expect(described_class.to_check).to contain_exactly(user_to_check)
    end

    it "only checks TL0 users" do
      user = Fabricate(:user, trust_level: 1)
      bouncer.move_to_state(user, DiscourseAkismet::Bouncer::PENDING_STATE)

      expect(described_class.to_check).to be_empty
    end

    it "re-checks skipped users" do
      user = Fabricate(:user, trust_level: 0)
      bouncer.move_to_state(user, DiscourseAkismet::Bouncer::SKIPPED_STATE)

      expect(described_class.to_check).to contain_exactly(user)
    end

    it "does not check skipped users created more than 24 hours ago" do
      user = Fabricate(:user, trust_level: 0, created_at: 2.days.ago)
      bouncer.move_to_state(user, DiscourseAkismet::Bouncer::SKIPPED_STATE)

      expect(described_class.to_check).to be_empty
    end
  end
end
