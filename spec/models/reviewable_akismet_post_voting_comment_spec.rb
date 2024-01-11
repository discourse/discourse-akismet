# frozen_string_literal: true

require "rails_helper"

describe "ReviewableAkismetPost" do
  fab!(:comment_poster) { Fabricate(:user) }
  fab!(:flagger) { Fabricate(:user, group_ids: [Group::AUTO_GROUPS[:trust_level_1]]) }
  fab!(:topic) { Fabricate(:topic, subtype: Topic::POST_VOTING_SUBTYPE) }
  fab!(:post) { Fabricate(:post, topic: topic) }
  fab!(:comment) { Fabricate(:post_voting_comment, user: comment_poster, post: post) }
  let(:guardian) { Guardian.new(flagger) }
  fab!(:admin)
  let(:admin_guardian) { Guardian.new(admin) }

  fab!(:moderator)
  fab!(:user)

  fab!(:reviewable) do
    Fabricate(:reviewable_akismet_post_voting_comment, target: comment, created_by: moderator)
  end

  describe "#build_actions" do
    it "Does not return available actions when the reviewable is no longer pending" do
      available_actions =
        (Reviewable.statuses.symbolize_keys.keys - [:pending]).reduce([]) do |actions, status|
          reviewable.status = Reviewable.statuses[status]
          an_action_id = :confirm_spam

          actions.concat reviewable_actions(guardian).to_a
        end

      expect(available_actions).to be_empty
    end

    it "Adds the confirm spam action" do
      actions = reviewable_actions(guardian)

      expect(actions.has?(:confirm_spam)).to be true
    end

    it "Adds the not spam action" do
      actions = reviewable_actions(guardian)

      expect(actions.has?(:not_spam)).to be true
    end

    it "Adds the dismiss action" do
      actions = reviewable_actions(guardian)

      expect(actions.has?(:ignore)).to be true
    end

    it "Adds the delete and delete + block actions" do
      admin = Fabricate(:admin)
      guardian = Guardian.new(admin)

      actions = reviewable_actions(guardian)

      expect(actions.has?(:delete_user)).to be true
      expect(actions.has?(:delete_user_block)).to be true
    end

    it "Excludes the confirm delete action when the user is not an staff member" do
      actions = reviewable_actions(guardian)

      expect(actions.has?(:confirm_delete)).to be false
    end

    def reviewable_actions(guardian)
      actions = Reviewable::Actions.new(reviewable, guardian, {})
      reviewable.build_actions(actions, guardian, {})

      actions
    end
  end

  describe "Performing actions on reviewable" do
    before { comment.trash!(admin) }

    shared_examples "a staff action logger" do
      it "Creates a UserHistory that reflects the action taken" do
        reviewable.perform admin, action

        admin_last_action = UserHistory.find_by(post: comment.post_id)

        assert_history_reflects_action(admin_last_action, admin, comment, action_name)
      end

      def assert_history_reflects_action(action, admin, comment, action_name)
        expect(action.custom_type).to eq action_name
        expect(action.post_id).to eq comment.post_id
        expect(action.topic_id).to eq comment.post.topic_id
      end

      it "Returns necessary information to update reviewable creator user stats" do
        result = reviewable.perform admin, action
        update_flag_stats = result.update_flag_stats

        expect(update_flag_stats[:status]).to eq flag_stat_status
        expect(update_flag_stats[:user_ids]).to match_array [reviewable.created_by_id]
      end
    end

    shared_examples "an Akismet feedback submission" do
      it "queues a job to submit feedback" do
        expect { reviewable.perform admin, action }.to change(
          Jobs::UpdateAkismetStatus.jobs,
          :size,
        ).by(1)
      end
    end

    describe "#perform_confirm_spam" do
      let(:action) { :confirm_spam }
      let(:action_name) { "confirmed_spam" }
      let(:flag_stat_status) { :agreed }

      it_behaves_like "a staff action logger"
      it_behaves_like "an Akismet feedback submission"

      it "Confirms spam and reviewable status is changed to approved" do
        result = reviewable.perform admin, action

        expect(result.transition_to).to eq :approved
      end
    end

    describe "#perform_not_spam" do
      let(:action) { :not_spam }
      let(:action_name) { "confirmed_ham" }
      let(:flag_stat_status) { :disagreed }

      it_behaves_like "a staff action logger"
      it_behaves_like "an Akismet feedback submission"

      it "Set post as clear and reviewable status is changed to rejected" do
        result = reviewable.perform admin, action

        expect(result.transition_to).to eq :rejected
      end

      it "Sends feedback to Akismet since post was not spam" do
        expect { reviewable.perform admin, action }.to change(
          Jobs::UpdateAkismetStatus.jobs,
          :size,
        ).by(1)
      end

      it "Recovers the post voting comment" do
        reviewable.perform admin, action

        recovered_comment = comment.reload

        expect(recovered_comment.deleted_at).to be_nil
        expect(recovered_comment.deleted_by).to be_nil
      end

      it "Does not try to recover the post voting comment if it was already recovered" do
        comment.update(deleted_at: nil)
        event_triggered = false
        blk = Proc.new { event_triggered = true }

        begin
          DiscourseEvent.on(:post_recovered, &blk)
          reviewable.perform admin, action

          expect(event_triggered).to eq false
        ensure
          DiscourseEvent.off(:post_recovered, &blk)
        end
      end
    end

    describe "#perform_ignore" do
      let(:action) { :ignore }
      let(:action_name) { "ignored" }
      let(:flag_stat_status) { :ignored }

      it_behaves_like "a staff action logger"

      it "Set post as dismissed and reviewable status is changed to ignored" do
        result = reviewable.perform admin, action

        expect(result.transition_to).to eq :ignored
      end
    end

    describe "#perform_delete_user" do
      let(:action) { :delete_user }
      let(:action_name) { "confirmed_spam_deleted" }
      let(:flag_stat_status) { :agreed }

      it_behaves_like "a staff action logger"
      it_behaves_like "an Akismet feedback submission"

      it "Confirms spam and reviewable status is changed to deleted" do
        result = reviewable.perform admin, action

        expect(result.transition_to).to eq :deleted
      end

      it "Deletes the user" do
        reviewable.perform admin, action

        expect(comment.reload.user).to be_nil
      end
    end

    describe "#perform_delete_user_block" do
      let(:action) { :delete_user_block }
      let(:action_name) { "confirmed_spam_deleted" }
      let(:flag_stat_status) { :agreed }

      it_behaves_like "a staff action logger"
      it_behaves_like "an Akismet feedback submission"

      it "Confirms spam and reviewable status is changed to deleted" do
        result = reviewable.perform admin, action

        expect(result.transition_to).to eq :deleted
      end

      it "Deletes the user" do
        reviewable.perform admin, action

        expect(comment.reload.user).to be_nil
      end
    end
  end

  describe "Performing actions on reviewable API errors" do
    let(:admin) { Fabricate(:admin) }
    let(:post) { Fabricate(:post_with_long_raw_content) }
    let(:reviewable) { ReviewableAkismetPost.needs_review!(target: post, created_by: admin).reload }

    describe "#perform_confirm_spam" do
      let(:action) { :confirm_spam }

      it "Ensures the post has been deleted" do
        reviewable.perform admin, action

        updated_post = post.reload

        expect(updated_post.deleted_at).not_to eq(nil)
      end
    end
  end
end
