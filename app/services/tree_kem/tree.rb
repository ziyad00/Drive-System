module TreeKem
  # A node in the ratchet tree. Leaves may hold a member; any node may hold
  # a public key ("occupied") once a commit has established one. Only public
  # material lives here — this mirrors the tree the server stores. Members
  # hold the matching private keys client-side.
  class Node
    attr_accessor :id, :left, :right, :parent, :pub, :member_id, :leaf

    def initialize(id)
      @id = id
      @leaf = false
    end

    def blank? = pub.nil?
    def occupied? = !pub.nil?

    # Node ids whose public key can receive a secret meant for everyone in
    # this subtree: the node itself if occupied, otherwise the occupied
    # descendants (falling through blanks to leaves). Blank leaves add none.
    def resolution
      return [ id ] if occupied?
      return [] if leaf

      left.resolution + right.resolution
    end

    def blank!
      self.pub = nil
    end
  end

  # Fixed-capacity (power-of-two) ratchet tree built from linked nodes.
  class Tree
    attr_reader :leaves, :root

    def initialize(capacity)
      @next_id = 0
      @leaves = Array.new(capacity) { build_leaf }
      @root = build_tree(@leaves)
    end

    def leaf_for(member_id)
      @leaves.find { |leaf| leaf.member_id == member_id }
    end

    # Internal nodes from a leaf's parent up to the root.
    def direct_path(leaf)
      path = []
      node = leaf.parent
      while node
        path << node
        node = node.parent
      end
      path
    end

    # Public snapshot for serialization / server storage.
    def public_state
      state = {}
      each_node { |n| state[n.id.to_s] = n.pub && Base64.strict_encode64(n.pub) }
      state
    end

    def load_public_state(state)
      # Keys are strings after a JSON round-trip; coerce so lookups hit.
      each_node do |n|
        encoded = state[n.id.to_s] || state[n.id]
        n.pub = encoded && Base64.decode64(encoded)
      end
    end

    def each_node(node = @root, &block)
      return if node.nil?

      yield node
      unless node.leaf
        each_node(node.left, &block)
        each_node(node.right, &block)
      end
    end

    private

    def build_leaf
      node = Node.new(@next_id)
      @next_id += 1
      node.leaf = true
      node
    end

    def build_tree(nodes)
      return nodes.first if nodes.length == 1

      parents = nodes.each_slice(2).map do |left, right|
        parent = Node.new(@next_id)
        @next_id += 1
        parent.left = left
        parent.right = right
        left.parent = parent
        right.parent = parent
        parent
      end
      build_tree(parents)
    end
  end
end
