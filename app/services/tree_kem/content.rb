module TreeKem
  # File-key hierarchy and content sealing for group E2EE. Each file gets a
  # random key; the file is sealed with streaming AES-256-GCM (STREAM
  # construction) under that key, and the file key is sealed under the
  # group's current epoch key. Membership changes rotate the epoch key; the
  # file key is then re-sealed under the new epoch key — the data itself is
  # never re-encrypted (key versioning / re-encryption).
  module Content
    CHUNK = 64 * 1024
    TAG = 16
    module_function

    def random_file_key = SecureRandom.random_bytes(32)

    # Seal a file key under a group/epoch key. Returns { epoch:, blob: }.
    def seal_file_key(file_key, epoch:, group_key:)
      { epoch: epoch, blob: box_seal(group_key, file_key, "file key epoch:#{epoch}") }
    end

    # Re-seal a file key from one epoch key to another without touching the
    # file's ciphertext.
    def reseal_file_key(sealed, old_group_key:, new_epoch:, new_group_key:)
      file_key = box_open(old_group_key, sealed[:blob], "file key epoch:#{sealed[:epoch]}")
      seal_file_key(file_key, epoch: new_epoch, group_key: new_group_key)
    end

    def open_file_key(sealed, group_key:)
      box_open(group_key, sealed[:blob], "file key epoch:#{sealed[:epoch]}")
    end

    # Streaming AEAD over content with a file key (per-chunk auth + final
    # flag so truncation/reordering are detected).
    def seal_content(file_key, data)
      prefix = SecureRandom.random_bytes(4)
      out = +"".b << prefix
      chunks = data.empty? ? [ "".b ] : data.b.bytes.each_slice(CHUNK).map { |s| s.pack("C*") }
      chunks.each_with_index do |chunk, i|
        final = i == chunks.length - 1
        sealed = chunk_cipher(:encrypt, file_key, prefix, i, final) do |c|
          c.update(chunk) + c.final
        end
        payload = sealed[:ct] + sealed[:tag]
        out << [ payload.bytesize ].pack("Q>") << payload
      end
      out
    end

    def open_content(file_key, ciphertext)
      prefix = ciphertext.byteslice(0, 4)
      body = ciphertext.byteslice(4..) || "".b
      plain = +"".b
      offset = 0
      index = 0
      until offset >= body.bytesize
        len = body.byteslice(offset, 8).unpack1("Q>")
        offset += 8
        blob = body.byteslice(offset, len)
        offset += len
        final = offset >= body.bytesize
        tag = blob.byteslice(-TAG, TAG)
        ct = blob.byteslice(0, blob.bytesize - TAG)
        plain << chunk_cipher(:decrypt, file_key, prefix, index, final, tag) { |c| c.update(ct) + c.final }
        index += 1
      end
      plain
    rescue OpenSSL::Cipher::CipherError
      raise "content failed authentication (tampered or truncated)"
    end

    def chunk_cipher(mode, key, prefix, index, final, tag = nil)
      cipher = OpenSSL::Cipher.new("aes-256-gcm").public_send(mode)
      cipher.key = key
      cipher.iv = prefix + [ index ].pack("Q>").byteslice(1, 7) + (final ? "\x01" : "\x00").b
      cipher.auth_tag = tag if mode == :decrypt
      result = yield(cipher)
      mode == :encrypt ? { ct: result, tag: cipher.auth_tag(TAG) } : result
    end

    def box_seal(key, plaintext, aad)
      cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
      cipher.key = key
      iv = cipher.random_iv
      cipher.auth_data = aad
      ct = cipher.update(plaintext) + cipher.final
      Base64.strict_encode64(iv + cipher.auth_tag + ct)
    end

    def box_open(key, blob, aad)
      raw = Base64.decode64(blob)
      cipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
      cipher.key = key
      cipher.iv = raw.byteslice(0, 12)
      cipher.auth_tag = raw.byteslice(12, 16)
      cipher.auth_data = aad
      cipher.update(raw.byteslice(28..)) + cipher.final
    end
  end
end
