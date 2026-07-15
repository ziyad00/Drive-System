module Storage
  # Common interface for all storage backends. An adapter stores and retrieves
  # raw bytes under a caller-supplied identifier and nothing more — metadata
  # is tracked by the Blob model, not the backend.
  class Base
    def initialize(config = {})
      @config = config.symbolize_keys
    end

    # Persist +data+ (raw bytes) under +id+.
    def store(id, data)
      raise NotImplementedError, "#{self.class}#store"
    end

    # Return the raw bytes stored under +id+, or raise Storage::NotFound.
    def retrieve(id)
      raise NotImplementedError, "#{self.class}#retrieve"
    end

    # Remove the bytes stored under +id+. Idempotent: deleting something
    # that does not exist is a no-op, so callers can retry compensation
    # paths safely.
    def delete(id)
      raise NotImplementedError, "#{self.class}#delete"
    end

    def name
      self.class.name.demodulize.underscore
    end

    private

    attr_reader :config

    # Blob ids are arbitrary strings (paths, UUIDs, anything), so they cannot
    # be used directly as file names or object keys. Hashing gives a fixed,
    # filesystem- and URL-safe key; the original id lives in the metadata table.
    def key_for(id)
      Digest::SHA256.hexdigest(id)
    end
  end
end
