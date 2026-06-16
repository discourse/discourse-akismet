# frozen_string_literal: true

require_dependency "reviewable_serializer"

class ReviewableAkismetUserSerializer < ReviewableSerializer
  payload_attributes :username, :name, :email, :bio, :external_error

  attributes :user_deleted, :link_admin

  def created_from_flag?
    true
  end

  def attributes(*args)
    data = super
    data[:payload]&.delete("email") if !include_email?
    data
  end

  def include_email?
    scope.can_check_emails?(scope.user)
  end

  def user_deleted
    object.target.nil?
  end

  def link_admin
    scope.is_staff? && object.target.present?
  end
end
