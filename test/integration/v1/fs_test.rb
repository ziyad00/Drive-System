require "test_helper"

module V1
  class FsTest < ActionDispatch::IntegrationTest
    setup do
      @user, token = ApiUser.generate!(name: "tree-user-#{SecureRandom.hex(4)}")
      @auth = { "Authorization" => "Bearer #{token}" }
    end

    def encode(text) = Base64.strict_encode64(text)

    def upload(path, content, extra = {})
      post "/v1/files", params: { path: path, data: encode(content) }.merge(extra),
           as: :json, headers: @auth
    end

    test "requires authentication" do
      get "/v1/fs/anything"

      assert_response :unauthorized
    end

    test "creates folders with missing parents" do
      post "/v1/folders", params: { path: "/docs/reports/2026" }, as: :json, headers: @auth

      assert_response :created
      assert_equal "/docs/reports/2026", response.parsed_body["path"]

      get "/v1/fs/docs", headers: @auth
      assert_response :success
      assert_equal [ "reports" ], response.parsed_body["children"].map { |c| c["name"] }
    end

    test "folder creation is idempotent" do
      post "/v1/folders", params: { path: "/docs" }, as: :json, headers: @auth
      assert_response :created

      post "/v1/folders", params: { path: "/docs" }, as: :json, headers: @auth
      assert_response :ok
    end

    test "uploads a file, creating parents, and reads it back by path" do
      upload("/docs/hello.txt", "Hello tree!", client_mtime: "2026-07-01T10:00:00Z")
      assert_response :created

      body = response.parsed_body
      assert_equal "file", body["kind"]
      assert_equal "/docs/hello.txt", body["path"]
      assert_equal "11", body["size"]
      assert_equal "text/plain", body["content_type"]
      assert_equal "2026-07-01T10:00:00Z", body["client_mtime"]

      get "/v1/fs/docs/hello.txt", headers: @auth
      assert_response :success
      assert_equal encode("Hello tree!"), response.parsed_body["data"]
    end

    test "listing the root shows top-level entries" do
      upload("/a.txt", "a")
      post "/v1/folders", params: { path: "/b" }, as: :json, headers: @auth

      get "/v1/fs", headers: @auth

      assert_response :success
      assert_equal "/", response.parsed_body["path"]
      assert_equal %w[b a.txt], response.parsed_body["children"].map { |c| c["name"] }
    end

    test "rejects duplicate paths and files as parents" do
      upload("/docs/a.txt", "a")
      assert_response :created

      upload("/docs/a.txt", "again")
      assert_response :conflict

      upload("/docs/a.txt/nested.txt", "impossible")
      assert_response :conflict
    end

    test "renames a file" do
      upload("/old.txt", "content")
      id = response.parsed_body["id"]

      patch "/v1/nodes/#{id}", params: { name: "new.txt" }, as: :json, headers: @auth

      assert_response :success
      assert_equal "/new.txt", response.parsed_body["path"]

      get "/v1/fs/old.txt", headers: @auth
      assert_response :not_found
      get "/v1/fs/new.txt", headers: @auth
      assert_response :success
    end

    test "moves a whole subtree in one operation without touching bytes" do
      upload("/projects/alpha/notes.txt", "deep")
      post "/v1/folders", params: { path: "/archive" }, as: :json, headers: @auth
      archive_id = response.parsed_body["id"]

      get "/v1/fs/projects/alpha", headers: @auth
      alpha_id = response.parsed_body["id"]

      patch "/v1/nodes/#{alpha_id}", params: { parent_id: archive_id }, as: :json, headers: @auth
      assert_response :success

      get "/v1/fs/archive/alpha/notes.txt", headers: @auth
      assert_response :success
      assert_equal encode("deep"), response.parsed_body["data"]

      get "/v1/fs/projects/alpha", headers: @auth
      assert_response :not_found
    end

    test "refuses to move a folder into its own subtree" do
      post "/v1/folders", params: { path: "/outer/inner" }, as: :json, headers: @auth
      inner_id = response.parsed_body["id"]
      get "/v1/fs/outer", headers: @auth
      outer_id = response.parsed_body["id"]

      patch "/v1/nodes/#{outer_id}", params: { parent_id: inner_id }, as: :json, headers: @auth

      assert_response :unprocessable_entity
    end

    test "copies a folder recursively with independent bytes" do
      upload("/src/one.txt", "one")
      upload("/src/sub/two.txt", "two")
      get "/v1/fs/src", headers: @auth
      src_id = response.parsed_body["id"]

      post "/v1/nodes/#{src_id}/copy",
           params: { parent_id: @user.root_node.id, name: "backup" }, as: :json, headers: @auth
      assert_response :created

      get "/v1/fs/backup/sub/two.txt", headers: @auth
      assert_equal encode("two"), response.parsed_body["data"]

      # Independent content: deleting the copy leaves the original intact.
      get "/v1/fs/backup", headers: @auth
      backup_id = response.parsed_body["id"]
      delete "/v1/nodes/#{backup_id}", params: { recursive: "true" }, headers: @auth
      assert_response :no_content

      get "/v1/fs/src/sub/two.txt", headers: @auth
      assert_response :success
    end

    test "permanently deleting a file purges its bytes and metadata" do
      upload("/doomed.txt", "bytes")
      node_id = response.parsed_body["id"]
      blob = Node.find(node_id).blob

      delete "/v1/nodes/#{node_id}", params: { permanent: "true" }, headers: @auth

      assert_response :no_content
      assert_not Blob.exists?(blob.id)
      assert_raises(Storage::NotFound) { Storage.backend(blob.backend).retrieve(blob.storage_id) }
    end

    test "permanent deletion of a non-empty folder requires recursive" do
      upload("/keep/file.txt", "x")
      get "/v1/fs/keep", headers: @auth
      folder_id = response.parsed_body["id"]

      delete "/v1/nodes/#{folder_id}", params: { permanent: "true" }, headers: @auth
      assert_response :unprocessable_entity

      delete "/v1/nodes/#{folder_id}", params: { permanent: "true", recursive: "true" }, headers: @auth
      assert_response :no_content
      assert_equal 0, @user.blobs.count
    end

    test "the root cannot be renamed, moved or deleted" do
      root_id = @user.root_node.id

      patch "/v1/nodes/#{root_id}", params: { name: "nope" }, as: :json, headers: @auth
      assert_response :unprocessable_entity

      delete "/v1/nodes/#{root_id}", headers: @auth
      assert_response :unprocessable_entity
    end

    test "trees are isolated between users" do
      upload("/secret/mine.txt", "private")
      mine_id = response.parsed_body["id"]

      _other, other_token = ApiUser.generate!(name: "other-#{SecureRandom.hex(4)}")
      other_auth = { "Authorization" => "Bearer #{other_token}" }

      get "/v1/fs/secret/mine.txt", headers: other_auth
      assert_response :not_found

      delete "/v1/nodes/#{mine_id}", headers: other_auth
      assert_response :not_found
    end

    test "file reads carry an ETag and honor If-None-Match" do
      upload("/tagged.txt", "content v1")
      etag = response.headers["ETag"]
      assert_match(/\A"\h{64}"\z/, etag)

      get "/v1/fs/tagged.txt", headers: @auth
      assert_equal etag, response.headers["ETag"]

      get "/v1/fs/tagged.txt", headers: @auth.merge("If-None-Match" => etag)
      assert_response :not_modified

      get "/v1/fs/tagged.txt", headers: @auth.merge("If-None-Match" => '"stale"')
      assert_response :success
    end

    test "PUT creates when missing and replaces when present" do
      put "/v1/files", params: { path: "/notes.txt", data: encode("first") }, as: :json, headers: @auth
      assert_response :created
      first_etag = response.headers["ETag"]

      put "/v1/files", params: { path: "/notes.txt", data: encode("second") }, as: :json, headers: @auth
      assert_response :ok
      assert_not_equal first_etag, response.headers["ETag"]

      get "/v1/fs/notes.txt", headers: @auth
      assert_equal encode("second"), response.parsed_body["data"]
      assert_equal 2, @user.blobs.count, "old content is retained as a version"
    end

    test "If-Match guards replacement against lost updates" do
      put "/v1/files", params: { path: "/doc.txt", data: encode("base") }, as: :json, headers: @auth
      etag = response.headers["ETag"]

      put "/v1/files", params: { path: "/doc.txt", data: encode("mine") }, as: :json,
          headers: @auth.merge("If-Match" => etag)
      assert_response :ok

      # A second writer still holding the old ETag loses cleanly.
      put "/v1/files", params: { path: "/doc.txt", data: encode("theirs") }, as: :json,
          headers: @auth.merge("If-Match" => etag)
      assert_response :precondition_failed

      get "/v1/fs/doc.txt", headers: @auth
      assert_equal encode("mine"), response.parsed_body["data"]
    end

    test "If-Match against a missing file fails the precondition" do
      put "/v1/files", params: { path: "/ghost.txt", data: encode("x") }, as: :json,
          headers: @auth.merge("If-Match" => '"anything"')

      assert_response :precondition_failed
    end

    test "PUT onto a folder is a conflict" do
      post "/v1/folders", params: { path: "/dir" }, as: :json, headers: @auth

      put "/v1/files", params: { path: "/dir", data: encode("x") }, as: :json, headers: @auth

      assert_response :conflict
    end

    test "invalid names are rejected" do
      upload("/bad", "x", path: "/..")
      assert_response :unprocessable_entity

      post "/v1/folders", params: { path: "/" }, as: :json, headers: @auth
      assert_response :unprocessable_entity
    end
  end
end
