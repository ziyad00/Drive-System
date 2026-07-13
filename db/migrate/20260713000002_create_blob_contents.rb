class CreateBlobContents < ActiveRecord::Migration[8.1]
  def change
    # Storage table for the database backend. Holds the actual bytes,
    # separate from the `blobs` metadata table.
    create_table :blob_contents do |t|
      t.string :blob_id, null: false
      t.binary :payload, null: false

      t.timestamps
    end

    add_index :blob_contents, :blob_id, unique: true
  end
end
