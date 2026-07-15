require "test_helper"

module V1
  class TrashTest < ActionDispatch::IntegrationTest
    setup do
      @user, token = ApiUser.generate!(name: "trash-user-#{SecureRandom.hex(4)}")
      @auth = { "Authorization" => "Bearer #{token}" }
    end

    def encode(text) = Base64.strict_encode64(text)

    def upload(path, content)
      post "/v1/files", params: { path: path, data: encode(content) }, as: :json, headers: @auth
    end

    test "deleting moves a subtree to the trash and out of the tree" do
      upload("/docs/keep.txt", "safe")
      get "/v1/fs/docs", headers: @auth
      folder_id = response.parsed_body["id"]

      delete "/v1/nodes/#{folder_id}", headers: @auth
      assert_response :no_content

      get "/v1/fs/docs", headers: @auth
      assert_response :not_found

      get "/v1/trash", headers: @auth
      entry = response.parsed_body.first
      assert_equal "docs", entry["name"]
      assert_equal "/docs", entry["trashed_from"]

      # Bytes still exist — trash is recoverable.
      assert_equal 1, @user.blobs.count
    end

    test "restore returns the subtree to its original place" do
      upload("/projects/plan.txt", "v1")
      get "/v1/fs/projects", headers: @auth
      folder_id = response.parsed_body["id"]

      delete "/v1/nodes/#{folder_id}", headers: @auth
      post "/v1/trash/#{folder_id}/restore", headers: @auth
      assert_response :success

      get "/v1/fs/projects/plan.txt", headers: @auth
      assert_response :success
      assert_equal encode("v1"), response.parsed_body["data"]
    end

    test "restore falls back to the root and renames on conflict" do
      upload("/report.txt", "old")
      old_id = response.parsed_body["id"]
      delete "/v1/nodes/#{old_id}", headers: @auth

      upload("/report.txt", "new")

      post "/v1/trash/#{old_id}/restore", headers: @auth
      assert_response :success
      assert_equal "/report (restored).txt", response.parsed_body["path"]

      get "/v1/fs/report.txt", headers: @auth
      assert_equal encode("new"), response.parsed_body["data"]
    end

    test "a deleted file frees its name immediately" do
      upload("/name.txt", "first")
      delete "/v1/nodes/#{response.parsed_body['id']}", headers: @auth

      upload("/name.txt", "second")

      assert_response :created
    end

    test "permanent deletion purges bytes, versions and trash entries" do
      upload("/gone.txt", "v1")
      node_id = response.parsed_body["id"]
      put "/v1/files", params: { path: "/gone.txt", data: encode("v2") }, as: :json, headers: @auth
      assert_equal 2, @user.blobs.count

      delete "/v1/nodes/#{node_id}", params: { permanent: "true" }, headers: @auth

      assert_response :no_content
      assert_equal 0, @user.blobs.count
      get "/v1/trash", headers: @auth
      assert_empty response.parsed_body
    end

    test "deleting from the trash purges for real" do
      upload("/temp.txt", "bytes")
      node_id = response.parsed_body["id"]
      delete "/v1/nodes/#{node_id}", headers: @auth

      delete "/v1/trash/#{node_id}", headers: @auth

      assert_response :no_content
      assert_equal 0, @user.blobs.count
    end

    test "emptying the trash purges everything in it" do
      upload("/a.txt", "a")
      a_id = response.parsed_body["id"]
      upload("/b.txt", "b")
      b_id = response.parsed_body["id"]
      delete "/v1/nodes/#{a_id}", headers: @auth
      delete "/v1/nodes/#{b_id}", headers: @auth

      delete "/v1/trash", headers: @auth

      assert_response :no_content
      assert_equal 0, @user.blobs.count
    end

    test "retention purges only expired entries" do
      upload("/old.txt", "old")
      old_id = response.parsed_body["id"]
      upload("/fresh.txt", "fresh")
      fresh_id = response.parsed_body["id"]
      delete "/v1/nodes/#{old_id}", headers: @auth
      delete "/v1/nodes/#{fresh_id}", headers: @auth
      Node.find(old_id).update_column(:trashed_at, 45.days.ago)

      assert_equal 1, Trash.purge_expired!

      get "/v1/trash", headers: @auth
      assert_equal [ fresh_id ], response.parsed_body.map { |entry| entry["id"] }
    end

    test "the trash is private to its owner" do
      upload("/mine.txt", "x")
      node_id = response.parsed_body["id"]
      delete "/v1/nodes/#{node_id}", headers: @auth

      _other, other_token = ApiUser.generate!(name: "other-#{SecureRandom.hex(4)}")
      other_auth = { "Authorization" => "Bearer #{other_token}" }

      get "/v1/trash", headers: other_auth
      assert_empty response.parsed_body

      post "/v1/trash/#{node_id}/restore", headers: other_auth
      assert_response :not_found
    end
  end
end
