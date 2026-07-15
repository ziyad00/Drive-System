require "test_helper"

module V1
  # End-to-end E2EE: two users form a group over the HTTP API and converge
  # on the same group key, while the server only ever stores public tree
  # state and encrypted commit secrets.
  class GroupsTest < ActionDispatch::IntegrationTest
    setup do
      @alice, @alice_key, @alice_auth = enroll("alice")
      @bob, @bob_key, @bob_auth = enroll("bob")
    end

    # Create a user, a TreeKem client, and publish the client's identity key
    # so the server uses it as the ratchet-tree leaf key.
    def enroll(name)
      user, token = ApiUser.generate!(name: "#{name}-#{SecureRandom.hex(4)}")
      client = TreeKem::Client.new(user.id)
      sig = Base64.strict_encode64(OpenSSL::PKey.generate_key("ED25519").public_to_der)
      put "/v1/identity",
          params: { kem_public_key: Base64.strict_encode64(client.identity_pub), sig_public_key: sig },
          as: :json, headers: { "Authorization" => "Bearer #{token}" }
      [ user, client, { "Authorization" => "Bearer #{token}" } ]
    end

    # Rebuild the public group locally from the server's state, so a client
    # can build or apply commits exactly as it would in a real deployment.
    def local_session(body)
      group = TreeKem::Group.create(capacity: body["capacity"])
      group.instance_variable_set(:@epoch, body["epoch"])
      body["members"].each { |m| group.tree.leaves.find { |l| l.id == m["leaf_id"] }.member_id = user_id(m["user"]) }
      group.tree.load_public_state(body["public_state"])
      group
    end

    def user_id(name) = ApiUser.find_by(name: name).id

    def show(id, auth)
      get "/v1/groups/#{id}", headers: auth
      response.parsed_body
    end

    def commit_as(client, id, auth)
      body = show(id, auth)
      session = local_session(body)
      message = session.commit(client)
      post "/v1/groups/#{id}/commits", params: { message: message }, as: :json, headers: auth
      message
    end

    test "two users form a group and derive the same key; server stores only ciphertext" do
      # Alice creates the group and commits the initial epoch.
      post "/v1/groups", params: { name: "secret-project", capacity: 4 }, as: :json, headers: @alice_auth
      assert_response :created
      gid = response.parsed_body["id"]
      commit_as(@alice_key, gid, @alice_auth)

      # Alice adds Bob, then commits again (now sealing a secret to Bob).
      post "/v1/groups/#{gid}/members", params: { user: @bob.name }, as: :json, headers: @alice_auth
      assert_response :created
      commit_as(@alice_key, gid, @alice_auth)

      # Bob syncs and applies the commit that admitted him.
      body = show(gid, @bob_auth)
      session = local_session(body)
      get "/v1/groups/#{gid}/commits?since=1", headers: @bob_auth
      response.parsed_body.each do |c|
        @bob_key.apply(session, deep_symbolize(c["message"]), body["members"].find { |m| m["user"] == @bob.name }["leaf_id"])
      end

      assert_not_nil @alice_key.group_key
      assert_equal @alice_key.group_key, @bob_key.group_key

      # What the server persisted is public keys + encrypted secrets only.
      stored = GroupCommit.where(encryption_group_id: gid).last
      secrets = JSON.parse(stored.message)["secrets"]
      assert secrets.any? { |s| s["blob"].present? }, "commit should carry encrypted secrets"
      refute EncryptionGroup.column_names.include?("group_key")
    end

    test "only the owner manages members" do
      post "/v1/groups", params: { name: "owned" }, as: :json, headers: @alice_auth
      gid = response.parsed_body["id"]

      post "/v1/groups/#{gid}/members", params: { user: @alice.name }, as: :json, headers: @bob_auth
      assert_response :forbidden
    end

    test "removing a member advances the epoch and blanks their leaf" do
      post "/v1/groups", params: { name: "team", capacity: 4 }, as: :json, headers: @alice_auth
      gid = response.parsed_body["id"]
      commit_as(@alice_key, gid, @alice_auth)
      post "/v1/groups/#{gid}/members", params: { user: @bob.name }, as: :json, headers: @alice_auth
      commit_as(@alice_key, gid, @alice_auth)
      epoch_before = show(gid, @alice_auth)["epoch"]

      delete "/v1/groups/#{gid}/members/#{@bob.name}", headers: @alice_auth
      assert_response :success
      commit_as(@alice_key, gid, @alice_auth)

      after = show(gid, @alice_auth)
      assert after["epoch"] > epoch_before
      assert_equal [ @alice.name ], after["members"].map { |m| m["user"] }
    end

    private

    def deep_symbolize(message)
      {
        epoch: message["epoch"],
        public_path: message["public_path"],
        secrets: message["secrets"].map do |sec|
          { for_node: sec["for_node"], path_index: sec["path_index"], node_id: sec["node_id"], blob: sec["blob"] }
        end
      }
    end
  end
end
