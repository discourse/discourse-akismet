# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserProfile do
  describe 'Callbacks to enqueue akismet checks' do
    before do
      SiteSetting.akismet_review_users = true
      SiteSetting.akismet_enabled = true
    end

    let(:user) do
      Fabricate(
        :user, 
        trust_level: TrustLevel[0], 
        user_auth_token_logs: [UserAuthTokenLog.new(client_ip: '127.0.0.1', action: 'an_action')]
      )
    end

    it 'triggers a job to check for spam when the bio changes' do
      user_profile = user.user_profile
      user_profile.bio_raw = "Check if I'm spam"

      assert_checks_triggered(user_profile, 1)
    end

    it "doesn't trigger a job when the the bio haven't changed" do
      assert_checks_triggered(user.user_profile, 0)
    end

    def assert_checks_triggered(user_profile, qty)
      expect {
        user_profile.save!
      }.to change(Jobs::CheckUsersForSpam.jobs, :size).by(qty)
    end
  end
end
