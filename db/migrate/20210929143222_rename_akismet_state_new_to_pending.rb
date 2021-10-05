# frozen_string_literal: true

class RenameAkismetStateNewToPending < ActiveRecord::Migration[6.1]
  def up
    execute "UPDATE post_custom_fields SET value = 'pending' WHERE name = 'AKISMET_STATE' AND value = 'new'"
    execute "UPDATE user_custom_fields SET value = 'pending' WHERE name = 'AKISMET_STATE' AND value = 'new'"
  end

  def down
    execute "UPDATE post_custom_fields SET value = 'new' WHERE name = 'AKISMET_STATE' AND value = 'pending'"
    execute "UPDATE user_custom_fields SET value = 'new' WHERE name = 'AKISMET_STATE' AND value = 'pending'"
  end
end
