class AddRocketchatThreadIdToIssues < ActiveRecord::Migration[5.2]
  def change
    unless column_exists?(:issues, :rocketchat_thread_id)
      add_column :issues, :rocketchat_thread_id, :string
      add_index :issues, :rocketchat_thread_id
    end
  end
end
