# frozen_string_literal: true

describe "Viewing reviewable akismet post voting comment" do
  fab!(:admin)
  fab!(:group)
  fab!(:comment_poster, :user)
  fab!(:topic) { Fabricate(:topic, subtype: Topic::POST_VOTING_SUBTYPE) }
  fab!(:post) { Fabricate(:post, topic: topic) }
  fab!(:comment) { Fabricate(:post_voting_comment, user: comment_poster, post: post) }
  fab!(:reviewable) do
    Fabricate(
      :reviewable_akismet_post_voting_comment,
      target: comment,
      topic: topic,
      created_by: Discourse.system_user,
    )
  end

  let(:review_page) { PageObjects::Pages::Review.new }

  before do
    SiteSetting.post_voting_enabled = true
    SiteSetting.post_voting_comment_enabled = true
    group.add(admin)
    sign_in(admin)
  end

  it "allows user to confirm reviewable as spam" do
    review_page.visit_reviewable(reviewable)

    expect(page).to have_text(comment.raw)

    PageObjects::Components::SelectKit.new(".post-voting-comment-confirm-spam").select_row_by_value(
      "post_voting_comment-confirm_spam",
    )
    expect(review_page).to have_reviewable_with_approved_status(reviewable)
  end

  it "allows the reviewer to mark the reviewable as not spam" do
    review_page.visit_reviewable(reviewable)

    PageObjects::Components::SelectKit.new(".post-voting-comment-not-spam").select_row_by_value(
      "post_voting_comment-not_spam",
    )
    expect(review_page).to have_reviewable_with_rejected_status(reviewable)
  end

  it "allows the reviewer to mark the reviewable as ignored" do
    review_page.visit_reviewable(reviewable)

    PageObjects::Components::SelectKit.new(".post-voting-comment-not-spam").select_row_by_value(
      "post_voting_comment-ignore",
    )

    expect(review_page).to have_reviewable_with_ignored_status(reviewable)
  end
end
