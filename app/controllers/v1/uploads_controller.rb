module V1
  # TUS-style resumable uploads: declare the file up front, send binary
  # chunks at the offset the server confirms, resume from HEAD after a
  # crash. The final chunk assembles the file through the same write path
  # as PUT /v1/files (create-or-replace, last-write-wins).
  class UploadsController < ApplicationController
    include BlobRequests
    include TreeNavigation

    # POST /v1/uploads {"path": ..., "size": ..., "content_type": ...,
    # "client_mtime": ..., "backend": ...}
    def create
      segments = split_path(params.require(:path))
      if segments.empty?
        return render json: { error: "path must name a file" }, status: :unprocessable_entity
      end

      size = params.require(:size).to_i
      max = Storage.config.fetch(:max_blob_bytes)
      if size <= 0 || size > max
        return render json: { error: "size must be between 1 and #{max} bytes" },
                      status: :content_too_large
      end

      upload = current_user.uploads.create!(
        path: "/#{segments.join('/')}",
        expected_size: size,
        content_type: params[:content_type].presence,
        client_mtime: params[:client_mtime].presence,
        backend: params[:backend].presence
      )

      response.headers["Upload-Length"] = upload.expected_size.to_s
      response.headers["Upload-Offset"] = "0"
      render json: upload_json(upload), status: :created
    end

    # HEAD /v1/uploads/:id — where to resume from.
    def show
      upload = find_upload or return
      response.headers["Upload-Length"] = upload.expected_size.to_s
      response.headers["Upload-Offset"] = upload.offset.to_s
      head :ok
    end

    # PATCH /v1/uploads/:id — raw binary chunk at Upload-Offset. An offset
    # mismatch is a 409 (the client must HEAD and resume from the server's
    # offset). The chunk completing the declared size finalizes the file.
    def append
      upload = find_upload or return

      client_offset = request.headers["Upload-Offset"].to_i
      if client_offset != upload.offset
        response.headers["Upload-Offset"] = upload.offset.to_s
        return render json: { error: "offset mismatch: server is at #{upload.offset}" },
                      status: :conflict
      end

      chunk = request.body.read.to_s
      return render json: { error: "empty chunk" }, status: :bad_request if chunk.empty?

      if upload.offset + chunk.bytesize > upload.expected_size
        return render json: { error: "chunk exceeds the declared size of #{upload.expected_size} bytes" },
                      status: :content_too_large
      end

      upload.append_chunk!(chunk)
      response.headers["Upload-Offset"] = upload.offset.to_s

      return render json: upload_json(upload), status: :ok unless upload.complete?

      node = finalize!(upload)
      etag_header!(node.blob)
      render json: node_json(node), status: :created
    end

    # DELETE /v1/uploads/:id — abort and discard staged bytes.
    def destroy
      upload = find_upload or return
      upload.destroy!
      head :no_content
    end

    private

    def find_upload
      upload = current_user.uploads.find_by(id: params[:id])
      render json: { error: "upload not found" }, status: :not_found unless upload
      upload
    end

    # Create-or-replace at the declared path, exactly like PUT /v1/files.
    def finalize!(upload)
      data = upload.staged_bytes
      segments = split_path(upload.path)
      name = segments.last

      node = resolve_path(upload.path)
      raise PathConflict, "#{upload.path} is a folder" if node&.folder?

      blob = BlobWriter.store!(user: current_user, blob_id: "fs/#{SecureRandom.uuid}",
                               data: data, backend_name: upload.backend)
      begin
        if node
          old_blob = node.blob
          old_type = node.content_type
          node.update!(blob: blob, content_type: resolved_type(upload, name, data),
                       client_mtime: upload.client_mtime || node.client_mtime)
          FileVersioning.record!(node, old_blob, old_type)
        else
          parent = ensure_folder_path(segments[0..-2])
          node = current_user.nodes.create!(
            parent: parent, kind: "file", name: name, blob: blob,
            content_type: resolved_type(upload, name, data),
            client_mtime: upload.client_mtime
          )
        end
      rescue StandardError
        BlobWriter.purge!(blob)
        raise
      end

      upload.destroy!
      node
    end

    def resolved_type(upload, name, data)
      upload.content_type.presence || Marcel::MimeType.for(StringIO.new(data), name: name)
    end

    def upload_json(upload)
      {
        id: upload.id,
        path: upload.path,
        size: upload.expected_size.to_s,
        offset: upload.offset.to_s,
        expires_at: (upload.updated_at + 48.hours).utc.iso8601
      }
    end
  end
end
