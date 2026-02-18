# frozen_string_literal: true

describe "Viewing reviewable akismet user" do
  fab!(:admin)
  fab!(:group)
  fab!(:reviewable, :reviewable_akismet_user)

  let(:review_page) { PageObjects::Pages::Review.new }

  before do
    group.add(admin)
    sign_in(admin)
  end

  it "allows user to confirm reviewable and delete user" do
    review_page.visit_reviewable(reviewable)

    review_page.select_bundled_action(reviewable, "user-delete_user")

    # TODO: Add this matcher to core page object.
    expect(review_page).to have_css(".review-item__status.--deleted")
  end

  it "allows user to confirm reviewable and delete and block user" do
    review_page.visit_reviewable(reviewable)

    review_page.select_bundled_action(reviewable, "user-delete_user_block")

    # TODO: Add this matcher to core page object.
    expect(review_page).to have_css(".review-item__status.--deleted")
  end

  it "allows the reviewer to mark the reviewable as rejected" do
    review_page.visit_reviewable(reviewable)

    page.find(".user-not-spam").click

    expect(review_page).to have_reviewable_with_rejected_status(reviewable)
  end

  it "displays username as a link to admin page for staff" do
    review_page.visit_reviewable(reviewable)

    expect(page).to have_link(
      reviewable.target.username,
      href: "/admin/users/#{reviewable.target.id}/#{reviewable.target.username}",
    )
  end
end
