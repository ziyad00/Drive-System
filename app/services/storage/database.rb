module Storage
  # Stores blob bytes in the blob_contents table — separate from the blobs
  # metadata table, which only tracks what was stored and where.
  class Database < Base
    def store(id, data)
      BlobContent.create!(blob_id: id, payload: data)
    end

    def retrieve(id)
      content = BlobContent.find_by(blob_id: id) or
        raise NotFound, "no database content for blob #{id.inspect}"

      content.payload
    end
  end
end
