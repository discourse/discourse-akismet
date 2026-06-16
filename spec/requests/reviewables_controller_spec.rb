# frozen_string_literal: true

RSpec.describe ReviewablesController do
  fab!(:moderator)
  fab!(:reviewable, :reviewable_akismet_user)

  before do
    SiteSetting.akismet_enabled = true
    SiteSetting.moderators_view_emails = false

    sign_in(moderator)
  end

  describe "#show" do
    it "filters the email payload by reviewer permission" do
      get "/review/#{reviewable.id}.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["reviewable"]["payload"]).not_to have_key("email")

      SiteSetting.moderators_view_emails = true

      get "/review/#{reviewable.id}.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["reviewable"]["payload"]["email"]).to eq(reviewable.target.email)
    end
  end
end
