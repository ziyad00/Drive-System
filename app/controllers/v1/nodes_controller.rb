module V1
  # Id-based mutations on tree nodes: rename, move, copy, delete.
  class NodesController < ApplicationController
    include BlobRequests
    include TreeNavigation

    before_action :set_node
    before_action :forbid_root

    # PATCH /v1/nodes/:id {"name": ...} renames; {"parent_id": ...} moves.
    # A move is a single parent_id update — atomic for a subtree of any
    # size, and it never touches storage.
    def update
      @node.name = params[:name].to_s if params.key?(:name)

      if params.key?(:parent_id)
        target = current_user.nodes.find_by(id: params[:parent_id])
        return render json: { error: "destination folder not found" }, status: :not_found unless target

        unless target.folder?
          return render json: { error: "destination is not a folder" }, status: :unprocessable_entity
        end

        if target == @node || target.descendant_of?(@node)
          return render json: { error: "cannot move a folder into itself" }, status: :unprocessable_entity
        end

        @node.parent = target
      end

      @node.save!
      render json: node_json(@node)
    end

    # POST /v1/nodes/:id/copy {"parent_id": ..., "name": ...}
    # Folders copy recursively; each copied file gets its own blob (bytes
    # are duplicated — chunk-level dedup is a later design).
    def copy
      target = current_user.nodes.find_by(id: params.require(:parent_id))
      return render json: { error: "destination folder not found" }, status: :not_found unless target

      unless target.folder?
        return render json: { error: "destination is not a folder" }, status: :unprocessable_entity
      end

      if @node.folder? && (target == @node || target.descendant_of?(@node))
        return render json: { error: "cannot copy a folder into itself" }, status: :unprocessable_entity
      end

      name = params[:name].presence || @node.name
      raise PathConflict, "destination already has #{name.inspect}" if target.children.exists?(name: name)

      copied_blobs = []
      copy = ActiveRecord::Base.transaction { deep_copy(@node, target, name, copied_blobs) }
      render json: node_json(copy), status: :created
    rescue StandardError => error
      # The transaction rolled the rows back; remove any bytes already written.
      copied_blobs&.each { |blob| Storage.backend(blob.backend).delete(blob.storage_id) }
      raise error
    end

    # DELETE /v1/nodes/:id — moves the subtree to the trash (recoverable,
    # so no recursive guard). permanent=true skips the trash and purges
    # bytes; non-empty folders then require recursive=true.
    def destroy
      if params[:permanent].to_s == "true"
        if @node.folder? && @node.children.exists? && params[:recursive].to_s != "true"
          return render json: { error: "folder is not empty (pass recursive=true)" },
                        status: :unprocessable_entity
        end

        @node.destroy!
      else
        Trash.trash!(@node)
      end

      head :no_content
    end

    private

    def set_node
      @node = current_user.nodes.find_by(id: params[:id])
      render json: { error: "node not found" }, status: :not_found unless @node
    end

    def forbid_root
      if @node&.sentinel?
        render json: { error: "the root folder cannot be modified" }, status: :unprocessable_entity
      end
    end

    def deep_copy(node, parent, name, copied_blobs)
      if node.file?
        bytes = Storage.backend(node.blob.backend).retrieve(node.blob.storage_id)
        blob = BlobWriter.store!(user: current_user, blob_id: "fs/#{SecureRandom.uuid}",
                                 data: bytes, backend_name: node.blob.backend)
        copied_blobs << blob
        current_user.nodes.create!(parent: parent, kind: "file", name: name, blob: blob,
                                   content_type: node.content_type, client_mtime: node.client_mtime)
      else
        folder = current_user.nodes.create!(parent: parent, kind: "folder", name: name)
        node.children.order(:id).each { |child| deep_copy(child, folder, child.name, copied_blobs) }
        folder
      end
    end
  end
end
