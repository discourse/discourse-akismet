# frozen_string_literal: true

describe "Viewing reviewable akismet user" do
  fab!(:admin)
  fab!(:reviewable, :reviewable_akismet_user)

  let(:review_page) { PageObjects::Pages::Review.new }
  let(:dialog) { PageObjects::Components::Dialog.new }

  before { sign_in(admin) }

  it "allows user to confirm reviewable and delete user" do
    review_page.visit_reviewable(reviewable)

    review_page.select_bundled_action(reviewable, "user-delete_user")
    confirm_deletion

    expect(review_page).to have_css(".review-item__status.--deleted")
  end

  it "allows user to confirm reviewable and delete and block user" do
    review_page.visit_reviewable(reviewable)

    review_page.select_bundled_action(reviewable, "user-delete_user_block")
    confirm_deletion

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

  # Core added a confirmation prompt to the delete user actions. Tolerate its
  # absence so this spec passes against older core revisions too.
  def confirm_deletion
    return if !Reviewable::Actions::Action.method_defined?(:confirm_destructive)

    expect(dialog).to have_content("@#{reviewable.target.username}")
    dialog.click_danger
  end
end
