class CreateUploads < ActiveRecord::Migration[8.1]
  def change
    # Resumable upload sessions. Chunks accumulate in a local staging file;
    # the row tracks how many bytes have been committed so a client can
    # resume after a crash. Finalization goes through the normal file
    # write path and removes the session.
    create_table :uploads do |t|
      t.references :api_user, null: false, foreign_key: true
      t.string :path, null: false
      t.bigint :expected_size, null: false
      t.bigint :offset, null: false, default: 0
      t.string :content_type
      t.datetime :client_mtime
      t.string :backend

      t.timestamps
    end
  end
end
