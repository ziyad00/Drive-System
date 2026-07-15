# A user's current published identity keys (public only). Publishing or
# rotating keys also appends to the tamper-evident key-transparency log.
class UserIdentity < ApplicationRecord
  belongs_to :api_user

  validates :kem_public_key, :sig_public_key, presence: true

  # base64(SHA-256(kem || sig)) — the value users compare out-of-band to
  # confirm they hold each other's real keys (defeats server substitution).
  def fingerprint
    digest = Digest::SHA256.digest("#{kem_public_key}\n#{sig_public_key}")
    Base64.strict_encode64(digest)
  end
end
