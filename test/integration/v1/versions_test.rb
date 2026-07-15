require "test_helper"

module V1
  class VersionsTest < ActionDispatch::IntegrationTest
    setup do
      @user, token = ApiUser.generate!(name: "ver-user-#{SecureRandom.hex(4)}")
      @auth = { "Authorization" => "Bearer #{token}" }
    end

    def encode(text) = Base64.strict_encode64(text)

    def put_file(path, content)
      put "/v1/files", params: { path: path, data: encode(content) }, as: :json, headers: @auth
    end

    test "replacing content records a version" do
      put_file("/doc.txt", "v1")
      node_id = response.parsed_body["id"]
      put_file("/doc.txt", "v2")

      get "/v1/nodes/#{node_id}/versions", headers: @auth

      assert_response :success
      versions = response.parsed_body
      assert_equal 1, versions.length
      assert_equal "2", versions.first["size"]
    end

    test "restore swaps a version in without losing the current content" do
      put_file("/doc.txt", "first")
      node_id = response.parsed_body["id"]
      put_file("/doc.txt", "second")

      get "/v1/nodes/#{node_id}/versions", headers: @auth
      version_id = response.parsed_body.first["id"]

      post "/v1/nodes/#{node_id}/versions/#{version_id}/restore", headers: @auth
      assert_response :success

      get "/v1/fs/doc.txt", headers: @auth
      assert_equal encode("first"), response.parsed_body["data"]

      # "second" is now itself a version — restoring is non-destructive.
      get "/v1/nodes/#{node_id}/versions", headers: @auth
      assert_equal 1, response.parsed_body.length

      post "/v1/nodes/#{node_id}/versions/#{response.parsed_body.first['id']}/restore", headers: @auth
      get "/v1/fs/doc.txt", headers: @auth
      assert_equal encode("second"), response.parsed_body["data"]
    end

    test "retention prunes the oldest versions and purges their bytes" do
      original = ENV["MAX_FILE_VERSIONS"]
      ENV["MAX_FILE_VERSIONS"] = "2"

      put_file("/doc.txt", "gen-0")
      node_id = response.parsed_body["id"]
      3.times { |i| put_file("/doc.txt", "gen-#{i + 1}") }

      get "/v1/nodes/#{node_id}/versions", headers: @auth
      assert_equal 2, response.parsed_body.length

      # current + 2 retained versions = 3 blobs total; older ones purged
      assert_equal 3, @user.blobs.count
    ensure
      original ? ENV["MAX_FILE_VERSIONS"] = original : ENV.delete("MAX_FILE_VERSIONS")
    end

    test "deleting a version purges its bytes" do
      put_file("/doc.txt", "keep")
      node_id = response.parsed_body["id"]
      put_file("/doc.txt", "current")

      get "/v1/nodes/#{node_id}/versions", headers: @auth
      version_id = response.parsed_body.first["id"]

      delete "/v1/nodes/#{node_id}/versions/#{version_id}", headers: @auth

      assert_response :no_content
      assert_equal 1, @user.blobs.count
    end

    test "deleting the file purges all version blobs" do
      put_file("/doc.txt", "a")
      node_id = response.parsed_body["id"]
      put_file("/doc.txt", "b")
      put_file("/doc.txt", "c")
      assert_equal 3, @user.blobs.count

      delete "/v1/nodes/#{node_id}", headers: @auth

      assert_response :no_content
      assert_equal 0, @user.blobs.count
    end

    test "folders have no versions" do
      post "/v1/folders", params: { path: "/dir" }, as: :json, headers: @auth
      folder_id = response.parsed_body["id"]

      get "/v1/nodes/#{folder_id}/versions", headers: @auth

      assert_response :unprocessable_entity
    end

    test "versions are private to their owner" do
      put_file("/doc.txt", "v1")
      node_id = response.parsed_body["id"]
      _other, other_token = ApiUser.generate!(name: "other-#{SecureRandom.hex(4)}")

      get "/v1/nodes/#{node_id}/versions", headers: { "Authorization" => "Bearer #{other_token}" }

      assert_response :not_found
    end
  end
end
