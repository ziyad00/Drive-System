module V1
  # Path-based reads over the file tree.
  class FsController < ApplicationController
    include BlobRequests
    include TreeNavigation

    # GET /v1/fs/*path — a folder renders with its children; a file renders
    # with its Base64 content.
    def show
      node = resolve_path(params[:path])
      return render json: { error: "no such path" }, status: :not_found unless node

      if node.folder?
        children = node.children.order(kind: :desc, name: :asc) # folders first
        render json: node_json(node).merge(children: children.map { |child| node_json(child) })
      else
        data = BlobWriter.read(node.blob)
        node.blob.backfill_checksum!(data)
        etag_header!(node.blob)
        return head :not_modified if if_none_match_hit?(node.blob)

        render json: node_json(node).merge(data: Base64.strict_encode64(data))
      end
    end
  end
end
