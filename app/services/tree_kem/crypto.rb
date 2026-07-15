require "openssl"

module TreeKem
  # Standard primitives only — X25519 for DH, HKDF-SHA256 for key
  # derivation, AES-256-GCM for AEAD. TreeKEM composes these; it never
  # invents a cipher.
  module Crypto
    module_function

    def generate_private
      OpenSSL::PKey.generate_key("X25519")
    end

    # A 32-byte seed deterministically yields an X25519 keypair, so a derived
    # path secret maps to a node keypair every member can recompute.
    def private_from_seed(seed)
      OpenSSL::PKey.new_raw_private_key("X25519", hkdf(seed, "treekem node key", 32))
    end

    def public_bytes(pkey)
      pkey.raw_public_key
    end

    def public_from_bytes(bytes)
      OpenSSL::PKey.new_raw_public_key("X25519", bytes)
    end

    def dh(private_key, peer_public)
      private_key.derive(peer_public)
    end

    def hkdf(secret, info, length = 32, salt: "")
      OpenSSL::KDF.hkdf(secret, salt: salt, info: info, length: length, hash: "SHA256")
    end

    # HPKE-style single-shot seal to a recipient public key: ephemeral DH →
    # HKDF → AES-256-GCM. Returns a self-describing blob.
    def seal_to(recipient_public_bytes, plaintext, aad = "")
      recipient = public_from_bytes(recipient_public_bytes)
      ephemeral = generate_private
      shared = dh(ephemeral, recipient)
      key = hkdf(shared, "treekem hpke", 32, salt: public_bytes(ephemeral))

      cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
      cipher.key = key
      iv = cipher.random_iv
      cipher.auth_data = aad
      ct = cipher.update(plaintext) + cipher.final
      # base64 fields so commit messages round-trip through JSON unchanged.
      { epk: b64(public_bytes(ephemeral)), iv: b64(iv), ct: b64(ct), tag: b64(cipher.auth_tag) }
    end

    def b64(bytes) = Base64.strict_encode64(bytes)
    def unb64(str) = Base64.decode64(str)

    def open_from(recipient_private, blob, aad = "")
      blob = blob.transform_keys(&:to_sym)
      epk = unb64(blob[:epk])
      ephemeral_public = public_from_bytes(epk)
      shared = dh(recipient_private, ephemeral_public)
      key = hkdf(shared, "treekem hpke", 32, salt: epk)

      cipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
      cipher.key = key
      cipher.iv = unb64(blob[:iv])
      cipher.auth_data = aad
      cipher.auth_tag = unb64(blob[:tag])
      cipher.update(unb64(blob[:ct])) + cipher.final
    end
  end
end
