# frozen_string_literal: true

class CreateNpnSubmissions < ActiveRecord::Migration[7.0]
  def change
    create_table :npn_submissions do |t|
      t.integer :user_id, null: false
      t.string :submission_type, null: false
      t.string :critique_style
      t.string :status, null: false, default: "draft"
      t.string :title
      t.jsonb :data, null: false, default: {}
      t.integer :topic_id
      t.text :error_message
      t.string :client_timezone
      t.datetime :submitted_at

      t.timestamps
    end

    add_index :npn_submissions, :user_id
    add_index :npn_submissions, :submission_type
    add_index :npn_submissions, :status
    add_index :npn_submissions, :topic_id
    add_index :npn_submissions, %i[user_id status submitted_at]
  end
end
