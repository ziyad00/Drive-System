# Answers "may this user reach this node, and how" — the single
# authorization point for owner-or-share access. A share on a folder
# covers its whole subtree, so access is granted if the user owns the node
# or holds an active share on the node or any of its ancestors.
class NodeAccess
  Result = Struct.new(:node, :permission, :via, :share) do
    def read? = permission.present?
    def write? = permission == "write"
    def owner? = via == :owner
  end

  def initialize(user)
    @user = user
  end

  # The node the user reaches at +path+, walking down from the owner's root
  # OR from a share root, with the effective permission. Returns nil if no
  # such node is visible to the user.
  def resolve_path(path)
    segments = path.to_s.split("/").reject(&:empty?)

    # Owner's own tree first.
    owned = walk(@user.root_node, segments)
    return Result.new(owned, "write", :owner, nil) if owned

    # Otherwise, the deepest share whose node is a prefix of the path.
    shared_access_for_path(segments)
  end

  # Permission for a node the caller already holds (by id), or nil.
  def for_node(node)
    return Result.new(node, "write", :owner, nil) if node.api_user_id == @user.id

    share = active_share_covering(node)
    share && Result.new(node, share.permission, :share, share)
  end

  # Nodes shared *with* this user, most-specific grants.
  def inbound_shares
    Share.active.where(grantee: @user).includes(:node, :created_by)
  end

  private

  def walk(root, segments)
    node = root
    segments.each do |segment|
      node = node.children.find_by(name: segment)
      return nil unless node
    end
    node
  end

  def shared_access_for_path(segments)
    inbound_shares.each do |share|
      base = share.node
      base_segments = base.self_and_ancestors.reverse.map(&:name)
      next unless segments.first(base_segments.length) == base_segments

      target = walk(base, segments.drop(base_segments.length))
      return Result.new(target, share.permission, :share, share) if target
    end
    nil
  end

  # The most-permissive active share on the node or any ancestor.
  def active_share_covering(node)
    ids = node.self_and_ancestors.map(&:id)
    Share.active.where(node_id: ids, grantee: @user).order(Arel.sql("permission = 'write' DESC")).first
  end
end
