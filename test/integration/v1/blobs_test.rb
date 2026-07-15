require "test_helper"

module V1
  class BlobsTest < ActionDispatch::IntegrationTest
    HELLO = Base64.strict_encode64("Hello Simple Storage World!")

    test "rejects requests without a token" do
      post "/v1/blobs", params: { id: "x", data: HELLO }, as: :json

      assert_response :unauthorized
    end

    test "rejects requests with a wrong token" do
      post "/v1/blobs", params: { id: "x", data: HELLO }, as: :json,
           headers: { "Authorization" => "Bearer wrong" }

      assert_response :unauthorized
    end

    test "stores and retrieves a blob" do
      id = "test-blob-#{SecureRandom.hex(4)}"

      post "/v1/blobs", params: { id: id, data: HELLO }, as: :json, headers: AUTH_HEADER
      assert_response :created

      get "/v1/blobs/#{id}", headers: AUTH_HEADER
      assert_response :success

      body = response.parsed_body
      assert_equal id, body["id"]
      assert_equal HELLO, body["data"]
      assert_equal "27", body["size"]
      assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/, body["created_at"])
    end

    test "accepts ids containing slashes" do
      id = "some/nested/path-#{SecureRandom.hex(4)}.bin"

      post "/v1/blobs", params: { id: id, data: HELLO }, as: :json, headers: AUTH_HEADER
      assert_response :created

      get "/v1/blobs/#{id}", headers: AUTH_HEADER
      assert_response :success
      assert_equal id, response.parsed_body["id"]
    end

    test "create responds with metadata only, not the payload" do
      id = "no-echo-#{SecureRandom.hex(4)}"

      post "/v1/blobs", params: { id: id, data: HELLO }, as: :json, headers: AUTH_HEADER

      assert_response :created
      body = response.parsed_body
      assert_equal id, body["id"]
      assert_equal "27", body["size"]
      assert_not_includes body.keys, "data"
    end

    test "rejects blobs larger than the configured maximum" do
      oversized = Base64.strict_encode64("x" * (Storage.config.fetch(:max_blob_bytes) + 1))

      post "/v1/blobs", params: { id: "too-big-#{SecureRandom.hex(4)}", data: oversized },
           as: :json, headers: AUTH_HEADER

      assert_response :content_too_large
      assert_equal 0, Blob.where("blob_id LIKE 'too-big-%'").count
    end

    test "rejects oversized request bodies at the middleware layer" do
      post "/v1/blobs", params: { id: "x", data: HELLO }, as: :json,
           headers: AUTH_HEADER.merge("CONTENT_LENGTH" => (100.megabytes).to_s)

      assert_response :content_too_large
    end

    test "rejects invalid base64 data" do
      post "/v1/blobs", params: { id: "bad-data-#{SecureRandom.hex(4)}", data: "not base64!!" },
           as: :json, headers: AUTH_HEADER

      assert_response :unprocessable_entity
      assert_equal 0, Blob.where("blob_id LIKE 'bad-data-%'").count
    end

    test "rejects missing fields" do
      post "/v1/blobs", params: { id: "no-data-#{SecureRandom.hex(4)}" }, as: :json, headers: AUTH_HEADER
      assert_response :bad_request

      post "/v1/blobs", params: { data: HELLO }, as: :json, headers: AUTH_HEADER
      assert_response :bad_request
    end

    test "rejects duplicate ids" do
      id = "dup-#{SecureRandom.hex(4)}"

      post "/v1/blobs", params: { id: id, data: HELLO }, as: :json, headers: AUTH_HEADER
      assert_response :created

      post "/v1/blobs", params: { id: id, data: HELLO }, as: :json, headers: AUTH_HEADER
      assert_response :conflict
    end

    test "lists stored blob metadata without data" do
      id = "list-me-#{SecureRandom.hex(4)}"
      post "/v1/blobs", params: { id: id, data: HELLO }, as: :json, headers: AUTH_HEADER

      get "/v1/blobs", headers: AUTH_HEADER
      assert_response :success

      entry = response.parsed_body.find { |blob| blob["id"] == id }
      assert_equal "27", entry["size"]
      assert_equal "local", entry["backend"]
      assert_not_includes entry.keys, "data"
    end

    test "listing requires authentication" do
      get "/v1/blobs"

      assert_response :unauthorized
    end

    test "stores into an explicitly requested backend" do
      id = "explicit-db-#{SecureRandom.hex(4)}"

      post "/v1/blobs", params: { id: id, data: HELLO, backend: "database" },
           as: :json, headers: AUTH_HEADER
      assert_response :created

      blob = Blob.find_by(blob_id: id)
      assert_equal "database", blob.backend
      assert BlobContent.exists?(blob_id: blob.storage_id)

      get "/v1/blobs/#{id}", headers: AUTH_HEADER
      assert_response :success
      assert_equal HELLO, response.parsed_body["data"]
    end

    test "rejects unknown or unconfigured backends" do
      post "/v1/blobs", params: { id: "x-#{SecureRandom.hex(4)}", data: HELLO, backend: "carrier-pigeon" },
           as: :json, headers: AUTH_HEADER
      assert_response :unprocessable_entity

      post "/v1/blobs", params: { id: "x-#{SecureRandom.hex(4)}", data: HELLO, backend: "s3" },
           as: :json, headers: AUTH_HEADER
      assert_response :unprocessable_entity
      assert_match(/not configured/, response.parsed_body["error"])
    end

    test "lists default and available backends" do
      get "/v1/backends", headers: AUTH_HEADER

      assert_response :success
      body = response.parsed_body
      assert_equal "local", body["default"]
      assert_includes body["available"], "local"
      assert_includes body["available"], "database"
      assert_not_includes body["available"], "s3"
    end

    test "users cannot see each other's blobs" do
      _owner, owner_token = ApiUser.generate!(name: "owner")
      _other, other_token = ApiUser.generate!(name: "other")
      id = "private-#{SecureRandom.hex(4)}"

      post "/v1/blobs", params: { id: id, data: HELLO }, as: :json,
           headers: { "Authorization" => "Bearer #{owner_token}" }
      assert_response :created

      get "/v1/blobs/#{id}", headers: { "Authorization" => "Bearer #{other_token}" }
      assert_response :not_found

      get "/v1/blobs", headers: { "Authorization" => "Bearer #{other_token}" }
      assert_empty response.parsed_body.select { |blob| blob["id"] == id }
    end

    test "different users can store under the same id without collisions" do
      _a, token_a = ApiUser.generate!(name: "alice")
      _b, token_b = ApiUser.generate!(name: "bob")
      id = "shared-name-#{SecureRandom.hex(4)}"
      data_a = Base64.strict_encode64("alice's bytes")
      data_b = Base64.strict_encode64("bob's bytes")

      post "/v1/blobs", params: { id: id, data: data_a }, as: :json,
           headers: { "Authorization" => "Bearer #{token_a}" }
      assert_response :created

      post "/v1/blobs", params: { id: id, data: data_b }, as: :json,
           headers: { "Authorization" => "Bearer #{token_b}" }
      assert_response :created

      get "/v1/blobs/#{id}", headers: { "Authorization" => "Bearer #{token_a}" }
      assert_equal data_a, response.parsed_body["data"]

      get "/v1/blobs/#{id}", headers: { "Authorization" => "Bearer #{token_b}" }
      assert_equal data_b, response.parsed_body["data"]
    end

    test "returns 404 for unknown blobs" do
      get "/v1/blobs/never-stored-#{SecureRandom.hex(4)}", headers: AUTH_HEADER

      assert_response :not_found
    end
  end
end
