class AddOwnerToBlobs < ActiveRecord::Migration[8.1]
  def change
    add_reference :blobs, :api_user, foreign_key: true, index: true

    # Blob ids are now unique per owner instead of globally, so different
    # users can store under the same id without leaking each other's
    # existence. Rows from before multi-tenancy keep a NULL owner.
    remove_index :blobs, :blob_id, unique: true
    add_index :blobs, [ :api_user_id, :blob_id ], unique: true
  end
end
