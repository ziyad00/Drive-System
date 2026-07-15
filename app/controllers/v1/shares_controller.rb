module V1
  # Manage shares on a node (owner only) and list shares received.
  class SharesController < ApplicationController
    include TreeNavigation

    rescue_from ActiveRecord::RecordInvalid do |error|
      status = error.record.errors.of_kind?(:grantee_id, :taken) ? :conflict : :unprocessable_entity
      render json: { error: error.record.errors.full_messages.to_sentence }, status: status
    end

    # GET /v1/shares — nodes shared with the current user.
    def index
      shares = NodeAccess.new(current_user).inbound_shares.order(created_at: :desc)
      render json: shares.map { |share| inbound_json(share) }
    end

    # GET /v1/nodes/:node_id/shares — grants the owner made on this node.
    def node_index
      node = owned_node!
      return unless node

      render json: node.shares.includes(:grantee).order(:created_at).map { |share| share_json(share) }
    end

    # POST /v1/nodes/:node_id/shares {"grantee": "name", "permission": "read|write", "expires_at": ...}
    def create
      node = owned_node!
      return unless node

      grantee = ApiUser.find_by(name: params.require(:grantee))
      return render json: { error: "no such user" }, status: :not_found unless grantee

      share = node.shares.create!(
        grantee: grantee, created_by: current_user,
        permission: params[:permission].presence || "read",
        expires_at: params[:expires_at].presence
      )
      render json: share_json(share), status: :created
    end

    # DELETE /v1/nodes/:node_id/shares/:id
    def destroy
      node = owned_node!
      return unless node

      share = node.shares.find_by(id: params[:id])
      return render json: { error: "no such share" }, status: :not_found unless share

      share.destroy!
      head :no_content
    end

    private

    def owned_node!
      node = current_user.nodes.find_by(id: params[:node_id])
      unless node
        render json: { error: "node not found" }, status: :not_found
        return nil
      end
      if node.sentinel?
        render json: { error: "this node cannot be shared" }, status: :unprocessable_entity
        return nil
      end
      node
    end

    def share_json(share)
      {
        id: share.id,
        node_id: share.node_id,
        grantee: share.grantee.name,
        permission: share.permission,
        expires_at: share.expires_at&.utc&.iso8601,
        created_at: share.created_at.utc.iso8601
      }
    end

    def inbound_json(share)
      {
        id: share.id,
        node_id: share.node_id,
        name: share.node.name,
        kind: share.node.kind,
        permission: share.permission,
        owner: share.created_by.name,
        expires_at: share.expires_at&.utc&.iso8601
      }
    end
  end
end
