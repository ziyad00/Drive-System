module TreeKem
  # A group member's client state: the private keys it holds (its long-term
  # leaf/identity key plus any internal-node keys it has derived) and the
  # current epoch's group key. Private material lives only here — never on
  # the server. This is the E2EE boundary.
  class Client
    attr_reader :member_id, :identity_pub, :epoch, :group_key

    def initialize(member_id)
      @member_id = member_id
      @identity = Crypto.generate_private
      @identity_pub = Crypto.public_bytes(@identity)
      @node_privs = {}
      @epoch = 0
    end

    def store_priv(node_id, priv)
      @node_privs[node_id] = priv
    end

    def set_epoch(epoch, key)
      @epoch = epoch
      @group_key = key
    end

    # Applies a commit built by another member: sync public tree state (done
    # by the caller), decrypt the one path secret meant for this member,
    # ratchet up to the root, and derive the new group key.
    def apply(group, commit, my_leaf_id)
      # Try the entry closest to the leaves first — that is this member's
      # true meeting point with the committer's path.
      openable = commit[:secrets]
        .select { |s| holds_key?(s[:for_node], my_leaf_id) }
        .sort_by { |s| s[:path_index] }

      entry = openable.first or raise "no path secret addressed to this member"
      aad = "epoch:#{commit[:epoch]}|node:#{entry[:node_id]}"
      path_secret = Crypto.open_from(private_for(entry[:for_node], my_leaf_id), entry[:blob], aad)

      # Derive this and every higher node's key, matching the committer.
      path = group.tree.direct_path(group.tree.leaves.find { |l| l.id == my_leaf_id })
      root_secret = nil
      path.drop_while { |n| n.id != entry[:node_id] }.each do |node|
        store_priv(node.id, Crypto.private_from_seed(path_secret))
        root_secret = path_secret
        path_secret = Crypto.hkdf(path_secret, "path ratchet")
      end

      set_epoch(commit[:epoch], group.group_key(root_secret))
    end

    private

    def holds_key?(node_id, my_leaf_id)
      node_id == my_leaf_id || @node_privs.key?(node_id)
    end

    def private_for(node_id, my_leaf_id)
      node_id == my_leaf_id ? @identity : @node_privs.fetch(node_id)
    end
  end
end
