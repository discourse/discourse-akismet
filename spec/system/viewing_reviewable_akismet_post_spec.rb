# frozen_string_literal: true

describe "Viewing reviewable akismet post" do
  fab!(:admin)
  fab!(:post)
  fab!(:reviewable) { Fabricate(:reviewable_akismet_post, target: post, topic: post.topic) }

  let(:review_page) { PageObjects::Pages::Review.new }

  before { sign_in(admin) }

  it "allows user to confirm reviewable as spam" do
    review_page.visit_reviewable(reviewable)

    expect(page).to have_text(post.raw)

    page.find(".post-confirm-spam").click
    expect_problem_confirmed(reviewable)
  end

  it "allows the reviewer to mark the reviewable as not spam" do
    post.trash!(admin)

    review_page.visit_reviewable(reviewable)

    review_page.select_bundled_action(reviewable, "post-not_spam")
    expect_no_problem_found(reviewable)
  end

  it "allows the reviewer to mark the reviewable as ignored" do
    review_page.visit_reviewable(reviewable)

    review_page.select_bundled_action(reviewable, "post-ignore")

    expect(review_page).to have_reviewable_with_ignored_status(reviewable)
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
    review_page.visit_reviewable(reviewable)

    expect(page).to have_text("Akismet API Error:")
    expect(page).to have_text("Rate limit exceeded")
  end

  # Core renamed its review status helpers by outcome. Fall back to the old
  # names so this spec passes against older core revisions too.
  def expect_problem_confirmed(reviewable)
    if review_page.respond_to?(:has_reviewable_with_problem_confirmed_status?)
      expect(review_page).to have_reviewable_with_problem_confirmed_status(reviewable)
    else
      expect(review_page).to have_reviewable_with_approved_status(reviewable)
    end
  end

  def expect_no_problem_found(reviewable)
    if review_page.respond_to?(:has_reviewable_with_no_problem_found_status?)
      expect(review_page).to have_reviewable_with_no_problem_found_status(reviewable)
    else
      expect(review_page).to have_reviewable_with_rejected_status(reviewable)
    end
  end
end
