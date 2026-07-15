module V1
  # Read content reachable through a share. Paths are resolved relative to
  # the grants the current user holds, so a grantee browses shared folders
  # and reads shared files without owning them.
  class SharedController < ApplicationController
    include BlobRequests
    include TreeNavigation

    # GET /v1/shared            -> everything shared with me (grant roots)
    # GET /v1/shared/<path>     -> a folder's children or a file's content
    def show
      segments = split_path(params[:path])
      if segments.empty?
        return render json: { shared: NodeAccess.new(current_user).inbound_shares.map { |s| grant_json(s) } }
      end

      access = NodeAccess.new(current_user).resolve_path(params[:path])
      return render json: { error: "not shared with you" }, status: :not_found unless access&.read? && !access.owner?

      node = access.node

      if node.folder?
        children = node.children.where(trashed_at: nil).order(kind: :desc, name: :asc)
        render json: node_json(node).merge(permission: access.permission,
                                           children: children.map { |c| node_json(c) })
      else
        data = BlobWriter.read(node.blob)
        node.blob.backfill_checksum!(data)
        etag_header!(node.blob)
        render json: node_json(node).merge(permission: access.permission,
                                           data: Base64.strict_encode64(data))
      end
    end

    # PUT /v1/shared/<path> — overwrite a shared file in place. Requires an
    # active write share. The replacement is stored under the file's owner
    # (it stays in their space and accounting) and versioned like any write.
    def update
      data = decode_base64!(params.require(:data))
      return unless enforce_blob_size!(data)

      access = NodeAccess.new(current_user).resolve_path(params[:path])
      return render json: { error: "not shared with you" }, status: :not_found unless access&.read? && !access.owner?

      node = access.node
      return render json: { error: "#{node.path} is a folder" }, status: :bad_request if node.folder?
      return render json: { error: "you have read-only access" }, status: :forbidden unless access.write?

      unless if_match_satisfied?(node.blob)
        return render json: { error: "precondition failed: file changed (ETag mismatch)" },
                      status: :precondition_failed
      end

      old_blob = node.blob
      old_type = node.content_type
      new_blob = BlobWriter.store!(user: node.api_user, blob_id: "fs/#{SecureRandom.uuid}",
                                   data: data, backend_name: old_blob.backend)
      begin
        node.update!(blob: new_blob, content_type: params[:content_type].presence || old_type)
      rescue StandardError
        BlobWriter.purge!(new_blob)
        raise
      end
      FileVersioning.record!(node, old_blob, old_type)

      etag_header!(node.blob)
      render json: node_json(node).merge(permission: access.permission)
    end

    private

    def grant_json(share)
      {
        node_id: share.node_id,
        name: share.node.name,
        kind: share.node.kind,
        permission: share.permission,
        owner: share.created_by.name
      }
    end
  end
end
