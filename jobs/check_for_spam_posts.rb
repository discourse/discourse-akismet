module Jobs
  class CheckForSpamPosts < ::Jobs::Scheduled
    every 10.minutes

    def execute(args)
      return if SiteSetting.akismet_api_key.blank?

      # Users above TL0 are checked in batches
      to_check = DiscourseAkismet.to_check
                                 .includes(:post => :user)
                                 .where('users.trust_level > 0')

      DiscourseAkismet.check_for_spam(to_check.map(&:post))
    end
  end
end
