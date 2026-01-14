# frozen_string_literal: true

describe "Viewing reviewable akismet post", type: :system do
  fab!(:admin)
  fab!(:group)
  fab!(:post)
  fab!(:reviewable) { Fabricate(:reviewable_akismet_post, target: post, topic: post.topic) }

  let(:refreshed_review_page) { PageObjects::Pages::RefreshedReview.new }

  before do
    SiteSetting.reviewable_old_moderator_actions = true
    group.add(admin)
    sign_in(admin)
  end

  it "allows user to confirm reviewable as spam" do
    refreshed_review_page.visit_reviewable(reviewable)

    expect(page).to have_text(post.raw)

    page.find(".post-confirm-spam").click
    expect(refreshed_review_page).to have_reviewable_with_approved_status(reviewable)
  end

  it "allows the reviewer to mark the reviewable as not spam" do
    post.trash!(admin)

    refreshed_review_page.visit_reviewable(reviewable)

    refreshed_review_page.select_bundled_action(reviewable, "post-not_spam")
    expect(refreshed_review_page).to have_reviewable_with_rejected_status(reviewable)
  end

  it "allows the reviewer to mark the reviewable as ignored" do
    refreshed_review_page.visit_reviewable(reviewable)

    refreshed_review_page.select_bundled_action(reviewable, "post-ignore")

    expect(refreshed_review_page).to have_reviewable_with_ignored_status(reviewable)
  end

  it "shows API errors if present" do
    reviewable.update(
      payload: {
        post_cooked: post.cooked,
        external_error: {
          error: "Rate limit exceeded",
          code: 429,
          msg: "Too many requests",
        },
      },
    )

    refreshed_review_page.visit_reviewable(reviewable)

    expect(page).to have_text("Akismet API Error:")
    expect(page).to have_text("Rate limit exceeded")
  end
end
