class CreateKeyTransparency < ActiveRecord::Migration[8.1]
  def change
    # A user's current published identity: two long-term PUBLIC keys
    # (X25519 for key agreement, Ed25519 for signing). Private keys are
    # generated client-side and never sent here.
    create_table :user_identities do |t|
      t.references :api_user, null: false, foreign_key: true, index: { unique: true }
      t.string :kem_public_key, null: false   # X25519, base64
      t.string :sig_public_key, null: false   # Ed25519, base64
      t.timestamps
    end

    # Append-only, hash-chained transparency log. Every identity publish or
    # change appends an entry; each entry commits to the previous one, so
    # the log cannot be rewritten without detection and clients can verify
    # inclusion and spot unexpected key changes.
    create_table :key_log_entries do |t|
      t.integer :seq, null: false
      t.references :api_user, null: false, foreign_key: true
      t.string :kem_public_key, null: false
      t.string :sig_public_key, null: false
      t.string :prev_hash, null: false
      t.string :entry_hash, null: false
      t.datetime :created_at, null: false
    end

    add_index :key_log_entries, :seq, unique: true
    add_index :key_log_entries, :entry_hash, unique: true
  end
end
