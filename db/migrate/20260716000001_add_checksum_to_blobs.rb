class AddChecksumToBlobs < ActiveRecord::Migration[8.1]
  def change
    # SHA-256 of the content; doubles as the HTTP ETag. Rows from before
    # this migration are backfilled lazily the first time they are read.
    add_column :blobs, :checksum, :string
  end
end
