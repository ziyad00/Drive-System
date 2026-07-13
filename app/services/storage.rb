# Single entry point to the pluggable storage backends. The active backend is
# chosen in config/simple_drive.yml (overridable via the STORAGE_BACKEND env
# variable); retrieval always goes through the backend recorded on the blob's
# metadata, so previously stored blobs keep working after a config change.
module Storage
  class Error < StandardError; end
  class NotFound < Error; end
  class ConfigurationError < Error; end

  ADAPTERS = {
    "s3"       => "Storage::S3",
    "database" => "Storage::Database",
    "local"    => "Storage::Local",
    "ftp"      => "Storage::Ftp"
  }.freeze

  class << self
    def current
      backend(config.fetch(:backend))
    end

    def backend(name)
      name = name.to_s
      class_name = ADAPTERS[name] or
        raise ConfigurationError, "unknown storage backend #{name.inspect} (available: #{ADAPTERS.keys.join(', ')})"

      adapters[name] ||= class_name.constantize.new(config.fetch(name.to_sym, {}))
    end

    def config
      Rails.application.config_for(:simple_drive)
    end

    def default_backend
      config.fetch(:backend).to_s
    end

    # Backends whose configuration is complete and can serve requests.
    def available_backends
      ADAPTERS.keys.select do |name|
        backend(name)
        true
      rescue ConfigurationError
        false
      end
    end

    # Used by tests to pick up config/env changes.
    def reset!
      adapters.clear
    end

    private

    def adapters
      @adapters ||= {}
    end
  end
end
