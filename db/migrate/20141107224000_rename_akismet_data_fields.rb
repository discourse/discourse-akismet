class RenameAkismetDataFields < ActiveRecord::Migration
  def change
    rename_table :akismet_data_fields, :akismet_spam_data
  end
end
