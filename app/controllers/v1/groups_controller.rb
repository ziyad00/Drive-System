module V1
  # E2EE group control plane. The server places members on the ratchet tree
  # and stores public state + opaque commits; it never sees a private key or
  # the group secret. Clients build and apply commits.
  class GroupsController < ApplicationController
    before_action :set_group, only: %i[show add_member remove_member commit commits]
    before_action :require_owner, only: %i[add_member remove_member]

    rescue_from ActionController::BadRequest do |error|
      render json: { error: error.message }, status: :unprocessable_entity
    end

    # POST /v1/groups {"name": "...", "capacity": 8}
    def create
      group = EncryptionGroup.create!(owner: current_user, name: params.require(:name),
                                      capacity: TreeKem::Group.round_up((params[:capacity] || 8).to_i))
      session = group.session
      leaf = session.add_member(current_user.id, identity_pub_for(current_user))
      persist(group, session)
      group.group_members.create!(api_user: current_user, leaf_id: leaf.id)

      render json: group_json(group), status: :created
    end

    # GET /v1/groups/:id — public state and membership, for clients to
    # rebuild the tree and build/apply commits.
    def show
      render json: group_json(@group)
    end

    # POST /v1/groups/:id/members {"user": "name"}
    def add_member
      user = ApiUser.find_by(name: params.require(:user)) or
        return render(json: { error: "no such user" }, status: :not_found)
      return render json: { error: "already a member" }, status: :conflict if @group.member?(user)

      session = @group.session
      begin
        leaf = session.add_member(user.id, identity_pub_for(user))
      rescue StandardError
        return render json: { error: "group is full" }, status: :unprocessable_entity
      end
      persist(@group, session)
      @group.group_members.create!(api_user: user, leaf_id: leaf.id)

      render json: group_json(@group), status: :created
    end

    # DELETE /v1/groups/:id/members/:user — blank the leaf and its path so
    # the next commit rekeys beyond the removed member's reach.
    def remove_member
      member = @group.group_members.joins(:api_user).find_by(api_users: { name: params[:user] }) or
        return render(json: { error: "not a member" }, status: :not_found)

      session = @group.session
      session.remove_member(member.api_user_id)
      persist(@group, session)
      member.destroy!

      render json: group_json(@group)
    end

    # POST /v1/groups/:id/commits {"message": {...}} — a member uploads a
    # commit it built locally. The server checks the epoch, stores the
    # opaque message, and advances the public tree.
    def commit
      return render json: { error: "not a member" }, status: :forbidden unless @group.member?(current_user)

      # The commit message is opaque E2EE data (public keys + ciphertext);
      # parse it as a plain hash rather than mass-assigning params.
      message = (JSON.parse(request.raw_post)["message"] rescue nil)
      return render json: { error: "malformed commit message" }, status: :bad_request unless message.is_a?(Hash)

      if message["epoch"].to_i != @group.epoch + 1
        return render json: { error: "stale epoch; fetch commits and rebuild" }, status: :conflict
      end

      session = @group.session
      message.fetch("public_path", {}).each do |node_id, pub|
        session.find(node_id.to_i).pub = Base64.decode64(pub)
      end
      session.instance_variable_set(:@epoch, message["epoch"].to_i)
      persist(@group, session)
      @group.group_commits.create!(committer: current_user, epoch: @group.epoch,
                                   message: message.to_json, created_at: Time.current)

      render json: { epoch: @group.epoch }, status: :created
    end

    # GET /v1/groups/:id/commits?since=<epoch>
    def commits
      list = @group.group_commits.where("epoch > ?", params[:since].to_i).order(:epoch)
      render json: list.map { |c| { epoch: c.epoch, committer: c.committer_id, message: JSON.parse(c.message) } }
    end

    private

    def set_group
      @group = EncryptionGroup.find_by(id: params[:id] || params[:group_id]) or
        render json: { error: "group not found" }, status: :not_found
    end

    def require_owner
      return if @group.nil? || @group.owner_id == current_user.id

      render json: { error: "only the group owner can manage members" }, status: :forbidden
    end

    # A member's published X25519 identity key is their ratchet-tree leaf key.
    def identity_pub_for(user)
      identity = user.user_identity or
        raise ActionController::BadRequest, "#{user.name} has not published an identity key"

      Base64.decode64(identity.kem_public_key)
    end

    def persist(group, session)
      group.update!(epoch: session.epoch, public_state: session.tree.public_state.to_json)
    end

    def group_json(group)
      {
        id: group.id,
        name: group.name,
        capacity: group.capacity,
        epoch: group.epoch,
        owner: group.owner.name,
        members: group.group_members.includes(:api_user).map { |m| { user: m.api_user.name, leaf_id: m.leaf_id } },
        public_state: group.public_state ? JSON.parse(group.public_state) : {}
      }
    end
  end
end
