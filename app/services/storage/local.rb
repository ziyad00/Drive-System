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

    # Write-to-temp-then-rename keeps the final path atomic: it only ever
    # holds nothing or the complete file, so a crash mid-write can never
    # leave a truncated blob that retrieve would happily serve.
    def store(id, data)
      path = path_for(id)
      FileUtils.mkdir_p(File.dirname(path))

      temp_path = "#{path}.tmp-#{SecureRandom.hex(8)}"
      begin
        File.binwrite(temp_path, data)
        File.rename(temp_path, path)
      rescue StandardError
        File.unlink(temp_path) if File.exist?(temp_path)
        raise
      end
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
