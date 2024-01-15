# frozen_string_literal: true

describe Jobs::CleanOldAkismetCustomFields do
  it "works" do
    SiteSetting.akismet_enabled = true

    post = Fabricate(:post)
    PostCustomField.create!(
      name: "AKISMET_IP_ADDRESS",
      value: "1.2.3",
      post: post,
      created_at: 3.months.ago,
    )

    described_class.new.execute({})

    expect(post.reload.custom_fields).to be_empty
  end
end
