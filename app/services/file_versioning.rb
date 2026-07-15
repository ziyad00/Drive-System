# Version history for file nodes. Replacements push the outgoing content
# onto the history; retention keeps the newest MAX_FILE_VERSIONS entries
# and purges the bytes of anything older.
module FileVersioning
  def self.max_versions
    Integer(ENV.fetch("MAX_FILE_VERSIONS", 10))
  end

  # Called with the blob (and its metadata) that is being replaced.
  def self.record!(node, old_blob, content_type)
    node.file_versions.create!(blob: old_blob, content_type: content_type)
    prune!(node)
  end

  def self.prune!(node)
    node.file_versions.order(id: :desc).offset(max_versions).each do |version|
      blob = version.blob
      version.destroy!
      BlobWriter.purge!(blob)
    end
  end

  # The version's content becomes current; the current content becomes the
  # newest version. Restoring never destroys data.
  def self.restore!(node, version)
    current_blob = node.blob
    current_type = node.content_type

    ActiveRecord::Base.transaction do
      node.update!(blob: version.blob, content_type: version.content_type)
      version.destroy!
      node.file_versions.create!(blob: current_blob, content_type: current_type)
    end

    prune!(node)
    node
  end
end
