# frozen_string_literal: true

require_dependency "reviewable_serializer"

class ReviewableAkismetPostSerializer < ReviewableSerializer
  payload_attributes :post_cooked, :external_error

  def created_from_flag?
    true
  end
end
