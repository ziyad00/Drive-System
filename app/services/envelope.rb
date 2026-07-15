require "openssl"
require "securerandom"

# Server-side envelope encryption. Each blob gets a fresh random 256-bit
# data key (DEK); content is sealed with AES-256-GCM using the STREAM
# construction (Hoang et al.): fixed-size chunks, each its own AEAD message,
# with a per-blob nonce prefix + chunk counter + final-chunk flag so
# reordering, truncation, and extension are all detected — not just
# corruption. The DEK itself is wrapped by the KMS master key and stored
# beside the ciphertext; the plaintext DEK never persists.
module Envelope
  CHUNK = 64 * 1024        # plaintext bytes per sealed chunk
  KEY_LEN = 32
  NONCE_PREFIX = 4         # random per-blob
  TAG = 16
  MAGIC = "SDE1"           # format marker + version

  module_function

  # data -> [ciphertext_bytes, wrapped_dek]
  def seal(data)
    dek = SecureRandom.random_bytes(KEY_LEN)
    prefix = SecureRandom.random_bytes(NONCE_PREFIX)
    out = +"".b << MAGIC << prefix

    chunks = data.empty? ? [ "".b ] : data.b.each_char.each_slice(CHUNK).map(&:join)
    chunks.each_with_index do |chunk, index|
      final = index == chunks.length - 1
      out << seal_chunk(dek, prefix, index, final, chunk)
    end

    [ out, Kms.wrap(dek) ]
  end

  # [ciphertext_bytes, wrapped_dek] -> data
  def open(ciphertext, wrapped_dek)
    raise Storage::Error, "unrecognized ciphertext format" unless ciphertext.byteslice(0, 4) == MAGIC

    dek = Kms.unwrap(wrapped_dek)
    prefix = ciphertext.byteslice(4, NONCE_PREFIX)
    body = ciphertext.byteslice(4 + NONCE_PREFIX..) || "".b

    plain = +"".b
    offset = 0
    index = 0
    sealed_chunk = TAG + 8 # tag + we prepend a 8-byte length header per chunk
    until offset >= body.bytesize
      len = body.byteslice(offset, 8).unpack1("Q>")
      offset += 8
      blob = body.byteslice(offset, len)
      offset += len
      final = offset >= body.bytesize
      plain << open_chunk(dek, prefix, index, final, blob)
      index += 1
    end

    plain
  end

  # A chunk is: 8-byte big-endian length of (ciphertext+tag), then that blob.
  def seal_chunk(dek, prefix, index, final, chunk)
    cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
    cipher.key = dek
    cipher.iv = nonce(prefix, index, final)
    sealed = cipher.update(chunk) + cipher.final
    payload = sealed + cipher.auth_tag(TAG)
    [ payload.bytesize ].pack("Q>") + payload
  end

  def open_chunk(dek, prefix, index, final, blob)
    tag = blob.byteslice(-TAG, TAG)
    body = blob.byteslice(0, blob.bytesize - TAG)
    cipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
    cipher.key = dek
    cipher.iv = nonce(prefix, index, final)
    cipher.auth_tag = tag
    cipher.update(body) + cipher.final
  rescue OpenSSL::Cipher::CipherError
    raise Storage::Error, "ciphertext failed authentication (tampered or truncated)"
  end

  # 12-byte GCM nonce: 4-byte blob prefix + 7-byte counter + 1-byte final flag.
  def nonce(prefix, index, final)
    prefix + [ index ].pack("Q>").byteslice(1, 7) + (final ? "\x01" : "\x00").b
  end
end
