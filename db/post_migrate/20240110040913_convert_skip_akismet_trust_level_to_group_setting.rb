# frozen_string_literal: true

class ConvertSkipAkismetTrustLevelToGroupSetting < ActiveRecord::Migration[7.0]
  def up
    old_setting_trust_level =
      DB.query_single(
        "SELECT value FROM site_settings WHERE name = 'skip_akismet_trust_level' LIMIT 1",
      ).first

    if old_setting_trust_level.present?
      allowed_groups = "1#{old_setting_trust_level}"

      DB.exec(
        "INSERT INTO site_settings(name, value, data_type, created_at, updated_at)
        VALUES('skip_akismet_groups', :setting, '20', NOW(), NOW())
        ON CONFLICT (name) DO NOTHING",
        setting: allowed_groups,
      )
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
