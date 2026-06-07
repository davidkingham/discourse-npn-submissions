# frozen_string_literal: true

class AddCaptionToNpnSubmissionUploads < ActiveRecord::Migration[7.0]
  # The original 20260519000002_create_npn_submission_uploads.rb was edited
  # after some sites had already deployed at that migration version to add
  # a `:caption` column for per-image notes. Rails won't re-run a
  # previously-applied migration, so those deployments are missing the
  # column — surfacing as `unknown attribute 'caption'` whenever
  # Submitter#persist_image_uploads writes a `variation` (additional)
  # image with a caption value.
  #
  # Adding the column idempotently here closes that gap without forcing
  # already-correct deployments to do anything: `if_not_exists: true`
  # short-circuits on freshly-built DBs (which got the column via the
  # updated create migration), and adds it on older deployments.
  def change
    add_column :npn_submission_uploads, :caption, :text, if_not_exists: true
  end
end
