require "test_helper"

module V1
  class UploadsTest < ActionDispatch::IntegrationTest
    setup do
      @user, token = ApiUser.generate!(name: "up-user-#{SecureRandom.hex(4)}")
      @auth = { "Authorization" => "Bearer #{token}" }
    end

    def start_upload(path, size, extra = {})
      post "/v1/uploads", params: { path: path, size: size }.merge(extra), as: :json, headers: @auth
      response.parsed_body["id"]
    end

    def send_chunk(id, bytes, offset)
      patch "/v1/uploads/#{id}", params: bytes,
            headers: @auth.merge("CONTENT_TYPE" => "application/offset+octet-stream",
                                 "Upload-Offset" => offset.to_s)
    end

    test "uploads a file in chunks and finalizes it" do
      id = start_upload("/big/movie.bin", 20)
      assert_response :created
      assert_equal "0", response.headers["Upload-Offset"]

      send_chunk(id, "0123456789", 0)
      assert_response :ok
      assert_equal "10", response.headers["Upload-Offset"]

      send_chunk(id, "abcdefghij", 10)
      assert_response :created
      assert_equal "file", response.parsed_body["kind"]
      assert_equal "/big/movie.bin", response.parsed_body["path"]

      get "/v1/dl/big/movie.bin", headers: @auth
      assert_equal "0123456789abcdefghij", response.body
      assert_not Upload.exists?(id), "session must be gone after finalize"
    end

    test "resumes from the server offset after a client crash" do
      id = start_upload("/resume.bin", 10)
      send_chunk(id, "01234", 0)

      # Client restarts, asks where it left off.
      head "/v1/uploads/#{id}", headers: @auth
      assert_response :ok
      assert_equal "5", response.headers["Upload-Offset"]
      assert_equal "10", response.headers["Upload-Length"]

      send_chunk(id, "56789", 5)
      assert_response :created
    end

    test "rejects out-of-sync chunks with the server offset" do
      id = start_upload("/sync.bin", 10)
      send_chunk(id, "01234", 0)

      send_chunk(id, "01234", 0) # replayed chunk

      assert_response :conflict
      assert_equal "5", response.headers["Upload-Offset"]
    end

    test "rejects declarations and chunks that exceed limits" do
      post "/v1/uploads", params: { path: "/huge.bin", size: Storage.config.fetch(:max_blob_bytes) + 1 },
           as: :json, headers: @auth
      assert_response :content_too_large

      id = start_upload("/small.bin", 5)
      send_chunk(id, "0123456789", 0)
      assert_response :content_too_large
    end

    test "finalizing replaces an existing file at the path" do
      post "/v1/files", params: { path: "/replace.bin", data: Base64.strict_encode64("old") },
           as: :json, headers: @auth

      id = start_upload("/replace.bin", 3)
      send_chunk(id, "new", 0)
      assert_response :created

      get "/v1/dl/replace.bin", headers: @auth
      assert_equal "new", response.body
      assert_equal 1, @user.blobs.count
    end

    test "aborting discards the session and staged bytes" do
      id = start_upload("/aborted.bin", 10)
      send_chunk(id, "01234", 0)
      staging = Upload.find(id).staging_path

      delete "/v1/uploads/#{id}", headers: @auth

      assert_response :no_content
      assert_not Upload.exists?(id)
      assert_not File.exist?(staging)
    end

    test "sessions are private to their user" do
      id = start_upload("/mine.bin", 10)
      _other, other_token = ApiUser.generate!(name: "other-#{SecureRandom.hex(4)}")

      head "/v1/uploads/#{id}", headers: { "Authorization" => "Bearer #{other_token}" }

      assert_response :not_found
    end

    test "stale sessions are purged by the maintenance task" do
      id = start_upload("/stale.bin", 10)
      send_chunk(id, "01234", 0)
      staging = Upload.find(id).staging_path
      Upload.find(id).update_column(:updated_at, 3.days.ago)

      Upload.stale.find_each(&:destroy!)

      assert_not Upload.exists?(id)
      assert_not File.exist?(staging)
    end
  end
end
