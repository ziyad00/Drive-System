module V1
  class FilesController < ApplicationController
    include BlobRequests
    include TreeNavigation

    rescue_from ActionController::BadRequest do |error|
      render json: { error: error.message }, status: :bad_request
    end

    # POST /v1/files {"path": "/docs/q3.pdf", "data": "<base64>",
    # "content_type": ..., "client_mtime": ..., "backend": ...}
    # Missing parent folders are created; the file's bytes go through the
    # same write path as the flat blob API.
    def create
      segments = split_path(params.require(:path))
      if segments.empty?
        return render json: { error: "path must name a file" }, status: :unprocessable_entity
      end

      data = decode_base64!(params.require(:data))
      return unless enforce_blob_size!(data)

      name = segments.pop
      parent = ensure_folder_path(segments)
      if parent.children.exists?(name: name)
        raise PathConflict, "#{parent.path == '/' ? '' : parent.path}/#{name} already exists"
      end

      blob = BlobWriter.store!(user: current_user, blob_id: "fs/#{SecureRandom.uuid}",
                               data: data, backend_name: params[:backend])
      begin
        node = current_user.nodes.create!(
          parent: parent, kind: "file", name: name, blob: blob,
          content_type: resolved_content_type(name, data),
          client_mtime: parsed_client_mtime
        )
      rescue StandardError
        BlobWriter.purge!(blob)
        raise
      end

      render json: node_json(node), status: :created
    end

    private

    def resolved_content_type(name, data)
      params[:content_type].presence ||
        Marcel::MimeType.for(StringIO.new(data), name: name)
    end

    def parsed_client_mtime
      value = params[:client_mtime].presence
      return nil unless value

      Time.iso8601(value.to_s)
    rescue ArgumentError
      raise ActionController::BadRequest, "client_mtime must be ISO 8601"
    end
  end
end
