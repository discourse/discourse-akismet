# frozen_string_literal: true

RSpec.describe Jobs::CheckForSpamUsers do
  before do
    SiteSetting.akismet_enabled = true
    SiteSetting.akismet_review_users = true
  end

  shared_examples "check users" do
    it "updates pending user's akismet state" do
      fake_client =
        mock(client_name).tap do |client|
          client.expects(:comment_check).returns(comment_check_result)
        end
      client_name.constantize.expects(:new).returns(fake_client)

      user =
        Fabricate(:user, trust_level: TrustLevel[0]).tap do |u|
          u.user_profile.update(bio_raw: "I am batman")
          UserAuthTokenLog.create!(client_ip: "127.0.0.1", action: "an_action", user: u)
        end

      DiscourseAkismet::UsersBouncer.new.move_to_state(
        user,
        DiscourseAkismet::Bouncer::PENDING_STATE,
      )

      subject.execute({})

      expect(user.reload.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]).to eq(
        expected_akismet_state,
      )
    end
  end

  context "with askimet" do
    let(:client_name) { "Akismet::Client" }

    before do
      SiteSetting.akismet_api_key = "fake_key"
      SiteSetting.anti_spam_service = DiscourseAkismet::AntiSpamService::AKISMET
    end

    context "with a spam user" do
      let(:comment_check_result) { "spam" }
      let(:expected_akismet_state) { "confirmed_spam" }

      include_examples "check users"
    end

    context "with a non-spam user" do
      let(:comment_check_result) { "ham" }
      let(:expected_akismet_state) { "confirmed_ham" }

      include_examples "check users"
    end
  end

  context "with netease" do
    let(:client_name) { "Netease::Client" }

    before do
      SiteSetting.anti_spam_service = DiscourseAkismet::AntiSpamService::NETEASE
      SiteSetting.netease_secret_id = "netease_id"
      SiteSetting.netease_secret_key = "netease_key"
      SiteSetting.netease_business_id = "business_id"
    end

    context "with a spam user" do
      let(:comment_check_result) { "spam" }
      let(:expected_akismet_state) { "confirmed_spam" }

      include_examples "check users"
    end

    context "with a non-spam user" do
      let(:comment_check_result) { "ham" }
      let(:expected_akismet_state) { "confirmed_ham" }

      include_examples "check users"
    end
  end
end
