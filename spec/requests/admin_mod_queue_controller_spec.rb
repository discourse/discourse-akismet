require 'rails_helper'

RSpec.describe DiscourseAkismet::AdminModQueueController do
  let(:admin) { Fabricate(:admin) }
  let(:post) { Fabricate(:post) }

  before do
    sign_in(admin)
    SiteSetting.akismet_enabled = true
    PostCustomField.create!(post: post, name: "AKISMET_STATE", value: "needs_review")
  end

  it "should include a post with excerpt" do
    get "/admin/plugins/akismet/index.json"
    expect(response.status).to eq(200)

    data = JSON.parse(response.body)
    expect(data["posts"][0]).to include("excerpt")
  end
end
