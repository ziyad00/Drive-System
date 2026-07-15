module V1
  class BlobsController < ApplicationController
    include BlobRequests

    # GET /v1/blobs — the current user's blobs; metadata only
    def index
      blobs = current_user.blobs.order(created_at: :desc).limit(200)

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
      return unless enforce_blob_size!(data)

      blob = BlobWriter.store!(user: current_user, blob_id: id, data: data,
                               backend_name: params[:backend])

      # The payload is not echoed back: the client already has it, and
      # re-encoding it would double the request's memory and bandwidth cost.
      render json: blob_metadata_json(blob), status: :created
    end

    # GET /v1/blobs/:id — only the owner's blobs are visible
    def show
      blob = current_user.blobs.find_by(blob_id: params[:id])
      return render json: { error: "blob not found" }, status: :not_found unless blob

      data = BlobWriter.read(blob)
      render json: blob_json(blob, data)
    end

    private

    def blob_json(blob, data)
      {
        id: blob.blob_id,
        data: Base64.strict_encode64(data),
        size: blob.size.to_s,
        created_at: blob.created_at.utc.iso8601
      }
    end

    def blob_metadata_json(blob)
      {
        id: blob.blob_id,
        size: blob.size.to_s,
        created_at: blob.created_at.utc.iso8601
      }
    end
  end
end
