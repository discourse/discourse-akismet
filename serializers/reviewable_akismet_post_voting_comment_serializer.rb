# frozen_string_literal: true

require_dependency "reviewable_serializer"

class ReviewableAkismetPostVotingCommentSerializer < ReviewableSerializer
  target_attributes :cooked
  payload_attributes :comment_cooked, :post_id, :external_error

  def created_from_flag?
    true
  end
end
