class CreateFileVersions < ActiveRecord::Migration[8.1]
  def change
    # Prior contents of a file node. Each version owns the blob that was
    # current before a replacement; retention pruning purges the oldest.
    create_table :file_versions do |t|
      t.references :node, null: false, foreign_key: true
      t.references :blob, null: false, foreign_key: true
      t.string :content_type

      t.timestamps
    end
  end
end
