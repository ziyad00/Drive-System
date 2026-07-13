module Storage
  # Stores blobs as files under a configured directory. Files are named by the
  # SHA-256 of the blob id and sharded into two-level subdirectories to keep
  # any single directory from growing unbounded.
  class Local < Base
    def initialize(config = {})
      super
      @root = config[:path].presence or
        raise ConfigurationError, "local backend requires a storage path"
    end

    def store(id, data)
      path = path_for(id)
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, data)
    end

    def retrieve(id)
      path = path_for(id)
      raise NotFound, "no local file for blob #{id.inspect}" unless File.file?(path)

      File.binread(path)
    end

    private

    def path_for(id)
      key = key_for(id)
      File.join(@root, key[0, 2], key[2, 2], key)
    end
  end
end
