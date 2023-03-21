# frozen_string_literal: true

class UpdateNeteaseSiteSettingValue < ActiveRecord::Migration[7.0]
  def up
    execute "UPDATE site_settings SET value = 'netease (Chinese)' WHERE name = 'anti_spam_service' AND value = 'netease'"
  end

  def down
    execute "UPDATE site_settings SET value = 'netease' WHERE name = 'anti_spam_service' AND value = 'netease (Chinese)'"
  end
end
