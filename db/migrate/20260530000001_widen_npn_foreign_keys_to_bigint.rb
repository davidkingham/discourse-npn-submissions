# frozen_string_literal: true

# Discourse core uses bigint primary keys throughout, so any column that
# stores a User/Topic/Upload id needs to be bigint too. The original
# `create_*` migrations declared these FK columns as `t.integer`, which the
# 32-bit signed int max (~2.1B) tolerates fine in a small local DB but
# overflows in Discourse's parallel-test CI environment where IDs are
# assigned in the 10-billion range (`10000000030 is out of range for
# ActiveModel::Type::Integer with limit 4 bytes`).
#
# Widening to `:bigint` is a metadata-only change in Postgres on tables
# with few rows; it doesn't rewrite the heap. Production safety: a small
# AccessExclusiveLock is taken on each table while the column type is
# upgraded — acceptable for these low-traffic, plugin-owned tables.
class WidenNpnForeignKeysToBigint < ActiveRecord::Migration[7.0]
  def up
    change_column :npn_submissions, :user_id, :bigint
    change_column :npn_submissions, :topic_id, :bigint
    change_column :npn_submission_uploads, :submission_id, :bigint
    change_column :npn_submission_uploads, :upload_id, :bigint
  end

  def down
    change_column :npn_submissions, :user_id, :integer
    change_column :npn_submissions, :topic_id, :integer
    change_column :npn_submission_uploads, :submission_id, :integer
    change_column :npn_submission_uploads, :upload_id, :integer
  end
end
