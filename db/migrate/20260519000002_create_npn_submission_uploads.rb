# frozen_string_literal: true

class CreateNpnSubmissionUploads < ActiveRecord::Migration[7.0]
  def change
    create_table :npn_submission_uploads do |t|
      t.integer :submission_id, null: false
      t.integer :upload_id, null: false
      t.string :role, null: false
      t.integer :position, null: false, default: 0
      t.text :caption

      t.timestamps
    end

    add_index :npn_submission_uploads, :submission_id
    add_index :npn_submission_uploads, :upload_id
    add_index :npn_submission_uploads,
              %i[submission_id role position],
              unique: true,
              name: "idx_npn_submission_uploads_ordering"
  end
end
