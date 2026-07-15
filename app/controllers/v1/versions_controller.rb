module V1
  # Version history of a file node.
  class VersionsController < ApplicationController
    include BlobRequests
    include TreeNavigation

    before_action :set_node

    # GET /v1/nodes/:node_id/versions — newest first
    def index
      versions = @node.file_versions.includes(:blob).order(id: :desc)
      render json: versions.map { |version| version_json(version) }
    end

    # POST /v1/nodes/:node_id/versions/:id/restore — the version becomes
    # current; the current content joins the history. Nothing is lost.
    def restore
      version = @node.file_versions.find_by(id: params[:id])
      return render json: { error: "version not found" }, status: :not_found unless version

      FileVersioning.restore!(@node, version)
      etag_header!(@node.blob)
      render json: node_json(@node.reload)
    end

    # DELETE /v1/nodes/:node_id/versions/:id — purge one version's bytes.
    def destroy
      version = @node.file_versions.find_by(id: params[:id])
      return render json: { error: "version not found" }, status: :not_found unless version

      blob = version.blob
      version.destroy!
      BlobWriter.purge!(blob)
      head :no_content
    end

    private

    def set_node
      @node = current_user.nodes.find_by(id: params[:node_id])
      return render json: { error: "node not found" }, status: :not_found unless @node

      render json: { error: "folders have no versions" }, status: :unprocessable_entity if @node.folder?
    end

    def version_json(version)
      {
        id: version.id,
        size: version.blob.size.to_s,
        etag: version.blob.etag,
        backend: version.blob.backend,
        content_type: version.content_type,
        created_at: version.created_at.utc.iso8601
      }
    end
  end
end
