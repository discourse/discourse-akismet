# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserDestroyer do
  fab!(:user) { Fabricate(:user) }
  fab!(:admin) { Fabricate(:admin) }
  fab!(:post) { Fabricate(:post, user_id: user.id) }
  fab!(:reviewable) { Fabricate(:reviewable_akismet_post, target_created_by: user, target: post) }

  before do
    SiteSetting.akismet_api_key = "akismetkey"
    SiteSetting.akismet_enabled = true
  end

  it "deletes reviewable when the `delete_posts` flag is enabled" do
    described_class.new(admin).destroy(user, delete_posts: true)
    expect { reviewable.reload }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
