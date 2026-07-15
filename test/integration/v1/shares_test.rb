require "test_helper"

module V1
  class SharesTest < ActionDispatch::IntegrationTest
    setup do
      @owner, owner_token = ApiUser.generate!(name: "owner-#{SecureRandom.hex(4)}")
      @friend, friend_token = ApiUser.generate!(name: "friend-#{SecureRandom.hex(4)}")
      @owner_auth = { "Authorization" => "Bearer #{owner_token}" }
      @friend_auth = { "Authorization" => "Bearer #{friend_token}" }
    end

    def b64(s) = Base64.strict_encode64(s)

    def upload(path, content, auth)
      post "/v1/files", params: { path: path, data: b64(content) }, as: :json, headers: auth
      response.parsed_body["id"]
    end

    test "sharing requires authentication" do
      get "/v1/shares"
      assert_response :unauthorized
    end

    test "owner shares a file and the grantee can read it but others cannot" do
      node_id = upload("/docs/report.txt", "confidential", @owner_auth)

      post "/v1/nodes/#{node_id}/shares",
           params: { grantee: @friend.name, permission: "read" }, as: :json, headers: @owner_auth
      assert_response :created

      # Friend sees it in "shared with me" and can read the content.
      get "/v1/shares", headers: @friend_auth
      assert_equal [ node_id ], response.parsed_body.map { |s| s["node_id"] }

      get "/v1/shared/docs/report.txt", headers: @friend_auth
      assert_response :success
      assert_equal b64("confidential"), response.parsed_body["data"]
      assert_equal "read", response.parsed_body["permission"]

      # A third user with no grant cannot.
      _stranger, stranger_token = ApiUser.generate!(name: "stranger-#{SecureRandom.hex(4)}")
      get "/v1/shared/docs/report.txt", headers: { "Authorization" => "Bearer #{stranger_token}" }
      assert_response :not_found
    end

    test "sharing a folder grants access to its whole subtree" do
      upload("/team/plans/q3.txt", "roadmap", @owner_auth)
      get "/v1/fs/team", headers: @owner_auth
      folder_id = response.parsed_body["id"]

      post "/v1/nodes/#{folder_id}/shares", params: { grantee: @friend.name }, as: :json, headers: @owner_auth
      assert_response :created

      get "/v1/shared/team/plans/q3.txt", headers: @friend_auth
      assert_response :success
      assert_equal b64("roadmap"), response.parsed_body["data"]

      get "/v1/shared/team/plans", headers: @friend_auth
      assert_response :success
      assert_equal "folder", response.parsed_body["kind"]
    end

    test "read shares cannot write, write shares can and history is kept" do
      node_id = upload("/shared.txt", "v1", @owner_auth)
      post "/v1/nodes/#{node_id}/shares", params: { grantee: @friend.name, permission: "read" },
           as: :json, headers: @owner_auth

      put "/v1/shared/shared.txt", params: { data: b64("hacked") }, as: :json, headers: @friend_auth
      assert_response :forbidden

      # Upgrade to write.
      share_id = @owner.nodes.find(node_id).shares.first.id
      delete "/v1/nodes/#{node_id}/shares/#{share_id}", headers: @owner_auth
      post "/v1/nodes/#{node_id}/shares", params: { grantee: @friend.name, permission: "write" },
           as: :json, headers: @owner_auth

      put "/v1/shared/shared.txt", params: { data: b64("v2 by friend") }, as: :json, headers: @friend_auth
      assert_response :success

      # Owner sees the new content and the old version is retained.
      get "/v1/fs/shared.txt", headers: @owner_auth
      assert_equal b64("v2 by friend"), response.parsed_body["data"]
      get "/v1/nodes/#{node_id}/versions", headers: @owner_auth
      assert_equal 1, response.parsed_body.length
    end

    test "expired shares are invisible" do
      node_id = upload("/temp.txt", "expiring", @owner_auth)
      post "/v1/nodes/#{node_id}/shares",
           params: { grantee: @friend.name, expires_at: 1.hour.ago.iso8601 }, as: :json, headers: @owner_auth
      assert_response :created

      get "/v1/shares", headers: @friend_auth
      assert_empty response.parsed_body

      get "/v1/shared/temp.txt", headers: @friend_auth
      assert_response :not_found
    end

    test "only the owner manages shares, and duplicate grants are rejected" do
      node_id = upload("/mine.txt", "x", @owner_auth)

      # Friend cannot share the owner's node.
      post "/v1/nodes/#{node_id}/shares", params: { grantee: @owner.name }, as: :json, headers: @friend_auth
      assert_response :not_found

      post "/v1/nodes/#{node_id}/shares", params: { grantee: @friend.name }, as: :json, headers: @owner_auth
      assert_response :created
      post "/v1/nodes/#{node_id}/shares", params: { grantee: @friend.name }, as: :json, headers: @owner_auth
      assert_response :conflict
    end

    test "revoking a share removes access" do
      node_id = upload("/revoke.txt", "secret", @owner_auth)
      post "/v1/nodes/#{node_id}/shares", params: { grantee: @friend.name }, as: :json, headers: @owner_auth
      share_id = response.parsed_body["id"]

      get "/v1/shared/revoke.txt", headers: @friend_auth
      assert_response :success

      delete "/v1/nodes/#{node_id}/shares/#{share_id}", headers: @owner_auth
      assert_response :no_content

      get "/v1/shared/revoke.txt", headers: @friend_auth
      assert_response :not_found
    end
  end
end
