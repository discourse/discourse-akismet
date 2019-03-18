require_dependency 'reviewable_serializer'

class ReviewableAkismetPostSerializer < ReviewableSerializer
  target_attributes :cooked, :raw
end
