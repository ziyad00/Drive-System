module V1
  class BlobsController < ApplicationController
    # GET /v1/blobs — metadata only; blob content stays in the storage backend
    def index
      blobs = Blob.order(created_at: :desc).limit(200)

      render json: blobs.map { |blob|
        {
          id: blob.blob_id,
          size: blob.size.to_s,
          backend: blob.backend,
          created_at: blob.created_at.utc.iso8601
        }
      }
    end

    # POST /v1/blobs
    def create
      id = params.require(:id).to_s
      data = decode_base64!(params.require(:data))

      if Blob.exists?(blob_id: id)
        return render json: { error: "blob #{id.inspect} already exists" }, status: :conflict
      end

      adapter = requested_adapter
      adapter.store(id, data)
      blob = Blob.create!(blob_id: id, size: data.bytesize, backend: adapter.name)

      render json: blob_json(blob, data), status: :created
    end

    # GET /v1/blobs/:id
    def show
      blob = Blob.find_by(blob_id: params[:id])
      return render json: { error: "blob not found" }, status: :not_found unless blob

      data = Storage.backend(blob.backend).retrieve(blob.blob_id)
      render json: blob_json(blob, data)
    end

    private

    # Precedence: explicit "backend" field on the request, then the user's
    # personal default, then the system-wide configured backend.
    def requested_adapter
      name = params[:backend].presence&.to_s || current_user.effective_backend

      unless Storage::ADAPTERS.key?(name)
        raise UnusableBackend, "unknown backend #{name.inspect} (available: #{Storage.available_backends.join(', ')})"
      end

      begin
        Storage.backend(name)
      rescue Storage::ConfigurationError
        raise UnusableBackend, "backend #{name.inspect} is not configured (available: #{Storage.available_backends.join(', ')})"
      end
    end

    class UnusableBackend < StandardError; end

    rescue_from UnusableBackend do |error|
      render json: { error: error.message }, status: :unprocessable_entity
    end

    def blob_json(blob, data)
      {
        id: blob.blob_id,
        data: Base64.strict_encode64(data),
        size: blob.size.to_s,
        created_at: blob.created_at.utc.iso8601
      }
    end

    def decode_base64!(value)
      Base64.strict_decode64(value.to_s)
    rescue ArgumentError
      raise InvalidBase64
    end

    class InvalidBase64 < StandardError; end

    rescue_from InvalidBase64 do
      render json: { error: "data is not valid Base64" }, status: :unprocessable_entity
    end

    rescue_from ActionController::ParameterMissing do |error|
      render json: { error: "missing required field: #{error.param}" }, status: :bad_request
    end

    rescue_from Storage::NotFound do
      render json: { error: "blob content not found in storage backend" }, status: :not_found
    end
  end
end
