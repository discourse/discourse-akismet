module Akismet
  class AkismetSpamData < ActiveRecord::Base
    self.table_name = 'akismet_spam_data'
    self.primary_key = 'id'

    belongs_to :post

    scope :needs_review, -> {where(state: "needs_review")}

    def mark_as_spam!
      update_attribute :state, "spam"
    end

    def mark_as_ham!
      update_attribute :state, "ham"
    end

    def mark_for_review!
      update_attribute :state, "needs_review"
    end

    def spam_suspect?
      state == "needs_review"
    end

    def new?
      state == "new"
    end

  end  
end
