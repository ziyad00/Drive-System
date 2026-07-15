class AddEncryptionToBlobs < ActiveRecord::Migration[8.1]
  def change
    # "plain" or "sse". When "sse", wrapped_dek holds the blob's data key
    # sealed by the KMS master key (never the plaintext DEK).
    add_column :blobs, :encryption, :string, null: false, default: "plain"
    add_column :blobs, :wrapped_dek, :text
  end
end
