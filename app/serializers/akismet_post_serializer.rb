require_dependency 'post_serializer'

class AkismetPostSerializer < PostSerializer
  attributes :excerpt

  def excerpt
    @excerpt ||= PrettyText.excerpt(cooked, 700, keep_emoji_images: true)
  end
end
