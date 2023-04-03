# frozen_string_literal: true

class AddAkismetIndexToPostCustomFields < ActiveRecord::Migration[7.0]
  def change
    add_index :post_custom_fields,
              [:post_id],
              name: "idx_akismet_post_custom_fields",
              where: "name = 'AKISMET_STATE' AND value = 'needs_review'"
  end
end
