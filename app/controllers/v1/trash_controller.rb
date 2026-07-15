module V1
  # The recycle bin: trashed subtree roots, restore, and permanent purging.
  class TrashController < ApplicationController
    include BlobRequests
    include TreeNavigation

    # GET /v1/trash — newest first
    def index
      trashed = current_user.trash_node.children
                            .where.not(trashed_at: nil)
                            .order(trashed_at: :desc)
      render json: trashed.map { |node| trashed_json(node) }
    end

    # POST /v1/trash/:id/restore — back to its original folder, or the tree
    # root if that folder is gone; renamed on name conflicts.
    def restore
      node = find_trashed or return
      Trash.restore!(node)
      render json: node_json(node.reload)
    end

    # DELETE /v1/trash/:id — permanent: purges nodes, versions and bytes.
    def destroy
      node = find_trashed or return
      node.destroy!
      head :no_content
    end

    # DELETE /v1/trash — empty the whole bin.
    def empty
      current_user.trash_node.children.find_each(&:destroy!)
      head :no_content
    end

    private

    def find_trashed
      node = current_user.trash_node.children.find_by(id: params[:id])
      render json: { error: "not in the trash" }, status: :not_found unless node
      node
    end

    def trashed_json(node)
      {
        id: node.id,
        kind: node.kind,
        name: node.original_name,
        trashed_from: node.trashed_from,
        trashed_at: node.trashed_at.utc.iso8601,
        purges_at: (node.trashed_at + Trash.retention_days.days).utc.iso8601
      }
    end
  end
end
