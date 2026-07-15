module TreeKem
  # The public group state — the ratchet tree the server stores. It builds
  # commits (driven by a committer who supplies private material via a
  # Client) and never itself holds a private key or the group secret.
  class Group
    attr_reader :tree, :epoch

    def self.create(capacity: 2)
      new(Tree.new(round_up(capacity)))
    end

    def self.round_up(n)
      size = 1
      size *= 2 while size < n
      size
    end

    def initialize(tree)
      @tree = tree
      @epoch = 0
    end

    def add_member(member_id, identity_pub)
      leaf = @tree.leaves.find { |l| l.member_id.nil? && l.blank? }
      leaf ||= grow_and_find
      leaf.member_id = member_id
      leaf.pub = identity_pub
      leaf
    end

    def remove_member(member_id)
      leaf = @tree.leaf_for(member_id) or raise "no such member"
      # Blank the leaf and its whole direct path so the removed member's old
      # keys can never open future secrets.
      leaf.member_id = nil
      leaf.blank!
      @tree.direct_path(leaf).each(&:blank!)
    end

    def members
      @tree.leaves.select(&:member_id).map(&:member_id)
    end

    # Builds a commit from +committer+: fresh keys down its direct path,
    # each path secret sealed to the resolution of the matching copath so
    # exactly the right members — and no others — can derive the new epoch.
    # Returns the commit message; mutates the public tree.
    def commit(committer, leaf_secret: SecureRandom.random_bytes(32))
      leaf = @tree.leaf_for(committer.member_id) or raise "committer not in group"
      @epoch += 1

      path = @tree.direct_path(leaf)
      secrets = []
      path_secret = Crypto.hkdf(leaf_secret, "path")
      prev = leaf
      root_secret = nil

      path.each_with_index do |node, index|
        priv = Crypto.private_from_seed(path_secret)
        node.pub = Crypto.public_bytes(priv)
        committer.store_priv(node.id, priv)

        copath = node.left.equal?(prev) ? node.right : node.left
        aad = "epoch:#{@epoch}|node:#{node.id}"
        copath.resolution.each do |target_id|
          target = find(target_id)
          secrets << { for_node: target_id, path_index: index, node_id: node.id,
                       blob: Crypto.seal_to(target.pub, path_secret, aad) }
        end

        root_secret = path_secret
        prev = node
        path_secret = Crypto.hkdf(path_secret, "path ratchet")
      end

      committer.set_epoch(@epoch, group_key(root_secret))

      { epoch: @epoch,
        public_path: path.each_with_object({}) { |n, h| h[n.id] = Base64.strict_encode64(n.pub) },
        secrets: secrets }
    end

    def group_key(root_secret)
      Crypto.hkdf(Crypto.hkdf(root_secret, "epoch"), "group application key", 32)
    end

    def find(id)
      node = nil
      @tree.each_node { |n| node = n if n.id == id }
      node
    end

    private

    def grow_and_find
      old = @tree.leaves
      bigger = Tree.new(old.length * 2)
      old.each_with_index do |leaf, i|
        bigger.leaves[i].member_id = leaf.member_id
        bigger.leaves[i].pub = leaf.pub
      end
      @tree = bigger
      @tree.leaves.find { |l| l.member_id.nil? }
    end
  end
end
