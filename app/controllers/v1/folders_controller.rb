module V1
  class FoldersController < ApplicationController
    include BlobRequests
    include TreeNavigation

    # POST /v1/folders {"path": "/docs/reports"} — creates the folder and
    # any missing parents (mkdir -p). Idempotent: an existing folder at the
    # path renders 200 instead of 201.
    def create
      segments = split_path(params.require(:path))
      if segments.empty?
        return render json: { error: "path must name a folder" }, status: :unprocessable_entity
      end

      existing = resolve_path(params[:path])
      if existing
        raise PathConflict, "#{existing.path} is a file" unless existing.folder?

        return render json: node_json(existing), status: :ok
      end

      folder = ensure_folder_path(segments)
      render json: node_json(folder), status: :created
    end
  end
end
