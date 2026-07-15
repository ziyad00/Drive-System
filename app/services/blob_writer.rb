# The one write path for blob content, shared by the flat blob API and the
# file tree. Metadata first — the unique index arbitrates concurrent ids
# before bytes move — then the backend write, with the row destroyed if the
# write fails so nothing is orphaned on either side.
class BlobWriter
  def self.store!(user:, blob_id:, data:, backend_name: nil)
    adapter = Storage.adapter_for(user: user, name: backend_name)
    blob = user.blobs.create!(blob_id: blob_id, size: data.bytesize, backend: adapter.name)

    begin
      adapter.store(blob.storage_id, data)
    rescue StandardError
      blob.destroy
      raise
    end

    blob
  end

  # Removes a blob's bytes and metadata. Idempotent at the backend layer.
  def self.purge!(blob)
    Storage.backend(blob.backend).delete(blob.storage_id)
    blob.destroy
  end
end
