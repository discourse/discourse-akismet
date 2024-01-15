# frozen_string_literal: true

RSpec.describe Jobs::ConfirmAkismetFlaggedPosts do
  describe "#execute" do
    subject(:execute) { described_class.new.execute(args) }

    let(:user) { Fabricate(:user) }
    let(:admin) { Fabricate(:admin) }
    let(:post) { Fabricate(:post, user: user) }
    let(:args) { { user_id: user.id, performed_by_id: admin.id } }
    let!(:reviewable) { ReviewableAkismetPost.needs_review!(target: post, created_by: admin) }

    context "when :user_id is not provided" do
      before { args.delete(:user_id) }

      it "raises an exception" do
        expect { execute }.to raise_error(Discourse::InvalidParameters)
      end
    end

    context "when :performed_by_id is not provided" do
      before { args.delete(:performed_by_id) }

      it "raises an exception if :performed_by_id is not provided" do
        expect { execute }.to raise_error(Discourse::InvalidParameters)
      end
    end

    it "approves every flagged post" do
      expect { execute }.to change { reviewable.reload.approved? }.to eq(true)
    end

    context "when the post was already deleted" do
      before { reviewable.target.trash! }
      it "approves every flagged post" do
        expect { execute }.to change { reviewable.reload.approved? }.to eq(true)
      end
    end

    context "when flagged post is not pending" do
      before { reviewable.perform(admin, :not_spam) }

      it "doesn't change it" do
        expect { execute }.not_to change { reviewable.reload.status }
      end
    end
  end
end
