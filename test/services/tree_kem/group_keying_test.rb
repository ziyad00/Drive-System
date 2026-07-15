require "test_helper"

module TreeKem
  class GroupKeyingTest < ActiveSupport::TestCase
    # Builds a group of n clients; the first commits so everyone converges.
    def build(n)
      clients = (1..n).map { |i| Client.new("m#{i}") }
      group = Group.create(capacity: n)
      clients.each { |c| group.add_member(c.member_id, c.identity_pub) }
      apply_commit(group, clients, clients.first)
      [ group, clients ]
    end

    def apply_commit(group, clients, committer)
      commit = group.commit(committer)
      clients.each do |c|
        next if c.member_id == committer.member_id

        leaf = group.tree.leaf_for(c.member_id)
        c.apply(group, commit, leaf.id) if leaf
      end
      commit
    end

    test "all members of a group derive the same key (N-party agreement)" do
      [ 2, 4, 8 ].each do |n|
        _group, clients = build(n)
        keys = clients.map(&:group_key)
        assert_equal 1, keys.uniq.length, "#{n} members did not converge"
        assert_equal 32, keys.first.bytesize
      end
    end

    test "the server never holds a private key or the group secret" do
      group, _clients = build(4)
      # The public tree stores only public keys; no group_key attribute exists.
      assert_not group.respond_to?(:group_secret)
      group.tree.each_node do |node|
        next if node.blank?

        key = OpenSSL::PKey.new_raw_public_key("X25519", node.pub)
        assert_raises(OpenSSL::PKey::PKeyError) { key.raw_private_key }
      end
    end

    test "removing a member rotates the key beyond their reach (forward secrecy)" do
      group, clients = build(4)
      old_key = clients.last.group_key
      removed_leaf_id = group.tree.leaf_for("m4").id

      group.remove_member("m4")
      commit = apply_commit(group, clients[0..2], clients[0])

      remaining = clients[0..2].map(&:group_key)
      assert_equal 1, remaining.uniq.length
      assert_not_equal old_key, remaining.first, "key must change on removal"

      assert_raises(RuntimeError) { clients[3].apply(group, commit, removed_leaf_id) }
      assert_not_equal remaining.first, clients[3].group_key
    end

    test "an added member joins the current key; membership changes advance epochs" do
      group, clients = build(4)
      assert_equal 1, group.epoch

      newcomer = Client.new("m5")
      group.add_member(newcomer.member_id, newcomer.identity_pub)
      apply_commit(group, clients + [ newcomer ], clients[0])

      active = ([ clients[0], clients[1], clients[2], clients[3], newcomer ]).map(&:group_key)
      assert_equal 1, active.uniq.length
      assert_equal 2, group.epoch
    end
  end

  class ContentTest < ActiveSupport::TestCase
    test "content seals and opens across chunk boundaries under a file key" do
      key = Content.random_file_key
      [ "", "hi", "z" * Content::CHUNK, Random.bytes(200_000) ].each do |data|
        sealed = Content.seal_content(key, data)
        assert_not_equal data, sealed if data.bytesize.positive?
        assert_equal data.b, Content.open_content(key, sealed)
      end
    end

    test "tampered content fails authentication" do
      key = Content.random_file_key
      sealed = Content.seal_content(key, "authentic")
      sealed.setbyte(sealed.bytesize - 1, sealed.getbyte(sealed.bytesize - 1) ^ 1)
      assert_raises(RuntimeError) { Content.open_content(key, sealed) }
    end

    test "file keys are re-sealed across epochs without re-encrypting data" do
      file_key = Content.random_file_key
      ciphertext = Content.seal_content(file_key, "shared document body")

      epoch1_key = SecureRandom.random_bytes(32)
      epoch2_key = SecureRandom.random_bytes(32)

      sealed_v1 = Content.seal_file_key(file_key, epoch: 1, group_key: epoch1_key)
      sealed_v2 = Content.reseal_file_key(sealed_v1, old_group_key: epoch1_key,
                                          new_epoch: 2, new_group_key: epoch2_key)

      # The new epoch's members recover the same file key from the resealed
      # wrapper and open the untouched ciphertext.
      recovered = Content.open_file_key(sealed_v2, group_key: epoch2_key)
      assert_equal file_key, recovered
      assert_equal "shared document body", Content.open_content(recovered, ciphertext)
      assert_equal 2, sealed_v2[:epoch]
    end
  end
end
