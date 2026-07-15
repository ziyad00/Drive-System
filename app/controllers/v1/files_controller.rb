module V1
  class FilesController < ApplicationController
    include BlobRequests
    include TreeNavigation

    rescue_from ActionController::BadRequest do |error|
      render json: { error: error.message }, status: :bad_request
    end

    # POST /v1/files {"path": "/docs/q3.pdf", "data": "<base64>",
    # "content_type": ..., "client_mtime": ..., "backend": ...}
    # Strict create: an existing path is a 409. Missing parent folders are
    # created; bytes go through the same write path as the flat blob API.
    def create
      segments = path_segments!
      data = decode_base64!(params.require(:data))
      return unless enforce_blob_size!(data)

      name = segments.pop
      parent = ensure_folder_path(segments)
      if parent.children.exists?(name: name)
        raise PathConflict, "#{parent.path == '/' ? '' : parent.path}/#{name} already exists"
      end

      node = write_file!(parent: parent, name: name, data: data)
      etag_header!(node.blob)
      render json: node_json(node), status: :created
    end

    # PUT /v1/files — create-or-replace with optimistic concurrency:
    # If-Match must equal the current ETag when supplied (412 otherwise,
    # including If-Match against a path that does not exist yet). Without
    # If-Match the defined conflict behavior is last-write-wins.
    def update
      segments = path_segments!
      data = decode_base64!(params.require(:data))
      return unless enforce_blob_size!(data)

      node = resolve_path(params[:path])
      raise PathConflict, "#{node.path} is a folder" if node&.folder?

      if node.nil?
        if request.headers["If-Match"].present?
          return render json: { error: "precondition failed: no such file" }, status: :precondition_failed
        end

        name = segments.pop
        node = write_file!(parent: ensure_folder_path(segments), name: name, data: data)
        status = :created
      else
        unless if_match_satisfied?(node.blob)
          return render json: { error: "precondition failed: file changed (ETag mismatch)" },
                        status: :precondition_failed
        end

        replace_content!(node, data)
        status = :ok
      end

      etag_header!(node.blob)
      render json: node_json(node), status: status
    end

    private

    def path_segments!
      segments = split_path(params.require(:path))
      raise ActionController::BadRequest, "path must name a file" if segments.empty?

      segments
    end

    def write_file!(parent:, name:, data:)
      blob = BlobWriter.store!(user: current_user, blob_id: "fs/#{SecureRandom.uuid}",
                               data: data, backend_name: params[:backend])
      begin
        current_user.nodes.create!(
          parent: parent, kind: "file", name: name, blob: blob,
          content_type: resolved_content_type(name, data),
          client_mtime: parsed_client_mtime
        )
      rescue StandardError
        BlobWriter.purge!(blob)
        raise
      end
    end

    # New bytes are written before the old ones are purged, so a failed
    # replace leaves the previous content intact.
    def replace_content!(node, data)
      old_blob = node.blob
      new_blob = BlobWriter.store!(user: current_user, blob_id: "fs/#{SecureRandom.uuid}",
                                   data: data, backend_name: params[:backend].presence || old_blob.backend)
      begin
        node.update!(
          blob: new_blob,
          content_type: params[:content_type].presence || node.content_type,
          client_mtime: parsed_client_mtime || node.client_mtime
        )
      rescue StandardError
        BlobWriter.purge!(new_blob)
        raise
      end

      BlobWriter.purge!(old_blob)
    end

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
