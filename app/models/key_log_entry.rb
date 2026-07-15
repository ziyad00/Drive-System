# One immutable entry in the append-only key-transparency log. Each entry's
# hash commits to the previous entry's hash, forming a chain: altering or
# dropping any past entry changes every hash after it.
class KeyLogEntry < ApplicationRecord
  belongs_to :api_user

  GENESIS = ("0" * 64).freeze

  # Appends a (user -> public keys) binding to the log under a row lock so
  # concurrent publishes get a consistent, gap-free chain.
  def self.append!(api_user:, kem_public_key:, sig_public_key:)
    transaction do
      tip = lock.order(seq: :desc).first
      seq = (tip&.seq || 0) + 1
      prev_hash = tip&.entry_hash || GENESIS
      created_at = Time.current
      entry_hash = hash_for(seq:, api_user_id: api_user.id, kem_public_key:,
                            sig_public_key:, prev_hash:, created_at:)

      create!(seq:, api_user:, kem_public_key:, sig_public_key:,
              prev_hash:, entry_hash:, created_at:)
    end
  end

  # Recompute the chain and confirm every stored hash matches — the check a
  # client (or auditor) runs to trust the log.
  def self.verify_chain
    prev = GENESIS
    order(:seq).each_with_index do |entry, i|
      return false unless entry.seq == i + 1
      return false unless entry.prev_hash == prev

      expected = hash_for(seq: entry.seq, api_user_id: entry.api_user_id,
                          kem_public_key: entry.kem_public_key, sig_public_key: entry.sig_public_key,
                          prev_hash: entry.prev_hash, created_at: entry.created_at)
      return false unless entry.entry_hash == expected

      prev = entry.entry_hash
    end
    true
  end

  def self.hash_for(seq:, api_user_id:, kem_public_key:, sig_public_key:, prev_hash:, created_at:)
    material = [ seq, api_user_id, kem_public_key, sig_public_key, prev_hash, created_at.utc.iso8601(6) ].join("|")
    Digest::SHA256.hexdigest(material)
  end
end
