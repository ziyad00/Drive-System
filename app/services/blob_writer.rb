# The one write/read path for blob content, shared by the flat blob API and
# the file tree. Metadata first — the unique index arbitrates concurrent ids
# before bytes move — then the backend write, with the row destroyed if the
# write fails so nothing is orphaned on either side.
#
# When server-side encryption is enabled, content is sealed with a per-blob
# data key before it reaches any backend and transparently opened on read;
# size and checksum (ETag) are always computed over the plaintext.
class BlobWriter
  def self.store!(user:, blob_id:, data:, backend_name: nil)
    adapter = Storage.adapter_for(user: user, name: backend_name)

    attrs = { blob_id: blob_id, size: data.bytesize, backend: adapter.name,
              checksum: Digest::SHA256.hexdigest(data) }
    payload = data
    if Storage.sse?
      payload, attrs[:wrapped_dek] = Envelope.seal(data)
      attrs[:encryption] = "sse"
    end

    blob = user.blobs.create!(attrs)
    begin
      adapter.store(blob.storage_id, payload)
    rescue StandardError
      blob.destroy
      raise
    end

    blob
  end

  # Plaintext bytes of a blob, decrypting transparently when encrypted.
  def self.read(blob)
    raw = Storage.backend(blob.backend).retrieve(blob.storage_id)
    return raw unless blob.encryption == "sse"

    Envelope.open(raw, blob.wrapped_dek)
  end

  # Removes a blob's bytes and metadata. Idempotent at the backend layer.
  def self.purge!(blob)
    Storage.backend(blob.backend).delete(blob.storage_id)
    blob.destroy
  end
end
