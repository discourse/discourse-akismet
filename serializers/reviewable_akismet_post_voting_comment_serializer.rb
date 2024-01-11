# frozen_string_literal: true

require_dependency "reviewable_serializer"

class ReviewableAkismetPostVotingCommentSerializer < ReviewableSerializer
  payload_attributes :comment_cooked, :post_id, :external_error
end
