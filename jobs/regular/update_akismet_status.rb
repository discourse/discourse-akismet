# frozen_string_literal: true

module Jobs
  class UpdateAkismetStatus < ::Jobs::Base
    def execute(args)
      return unless SiteSetting.akismet_enabled?

      akismet_feedback = args[:feedback]
      status = args[:status]
      raise Discourse::InvalidParameters.new(:feedback) unless akismet_feedback
      raise Discourse::InvalidParameters.new(:status) unless status

      client = DiscourseAkismet::AntiSpamService.client
      client.submit_feedback(status, akismet_feedback)
    end
  end
end
