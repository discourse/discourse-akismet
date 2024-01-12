# frozen_string_literal: true

require "rails_helper"

RSpec.describe Jobs::CheckForSpamPostsVotingComments do
  fab!(:topic) { Fabricate(:topic, subtype: Topic::POST_VOTING_SUBTYPE) }
  fab!(:post) { Fabricate(:post, topic: topic) }
  fab!(:comment) { Fabricate(:post_voting_comment, post: post) }

  before do
    SiteSetting.akismet_api_key = "test"
    stub_request(:post, "https://test.rest.akismet.com/1.1/comment-check").to_return(
      status: 200,
      body: "true",
    )
    bouncer = DiscourseAkismet::PostVotingCommentsBouncer.new
    bouncer.store_additional_information(comment, { ip_address: "", user_agent: "", referrer: "" })
    bouncer.move_to_state(comment, DiscourseAkismet::Bouncer::PENDING_STATE)
  end

  it "does not trigger event if akismet is disabled" do
    event =
      DiscourseEvent.track(:akismet_found_spam) do
        Jobs::CheckForSpamPostsVotingComments.new.execute(nil)
      end
    expect(event).not_to be_present
  end

  # not possible to test that the event is not triggerd due to absence of post_voting_enabled

  it "does not trigger event if post_voting is disabled" do
    SiteSetting.akismet_enabled = true
    SiteSetting.post_voting_enabled = false

    event =
      DiscourseEvent.track(:akismet_found_spam) do
        Jobs::CheckForSpamPostsVotingComments.new.execute(nil)
      end

    expect(event).not_to be_present
  end

  it "triggers an event when a pending comment exists" do
    SiteSetting.akismet_enabled = true
    SiteSetting.post_voting_enabled = true

    event =
      DiscourseEvent.track(:akismet_found_spam) do
        Jobs::CheckForSpamPostsVotingComments.new.execute(nil)
      end

    expect(event).to be_present
  end
end
