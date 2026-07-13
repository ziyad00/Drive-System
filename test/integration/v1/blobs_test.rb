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

    test "returns 404 for unknown blobs" do
      get "/v1/blobs/never-stored-#{SecureRandom.hex(4)}", headers: AUTH_HEADER

      assert_response :not_found
    end
  end
end
