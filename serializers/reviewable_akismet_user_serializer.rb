# frozen_string_literal: true

require_dependency "reviewable_serializer"

class ReviewableAkismetUserSerializer < ReviewableSerializer
  payload_attributes :username, :name, :email, :bio, :external_error

  attributes :user_deleted

  def created_from_flag?
    true
  end

  def user_deleted
    object.target.nil?
  end
end
