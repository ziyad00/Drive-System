require "test_helper"

module V1
  class BackendsTest < ActionDispatch::IntegrationTest
    HELLO = Base64.strict_encode64("Hello Simple Storage World!")

    setup do
      @user, token = ApiUser.generate!(name: "backend-switcher")
      @auth = { "Authorization" => "Bearer #{token}" }
    end

    test "requires authentication" do
      get "/v1/backends"

      assert_response :unauthorized
    end

    test "reports available backends and defaults" do
      get "/v1/backends", headers: @auth

      assert_response :success
      body = response.parsed_body
      assert_includes body["available"], "local"
      assert_includes body["available"], "database"
      assert_equal "local", body["system_default"]
      assert_equal "local", body["default"]
      assert_nil body["user_default"]
    end

    test "setting a personal default changes where blobs go" do
      put "/v1/backends/default", params: { backend: "database" }, as: :json, headers: @auth
      assert_response :success
      assert_equal "database", response.parsed_body["default"]
      assert_equal "database", response.parsed_body["user_default"]

      id = "user-default-#{SecureRandom.hex(4)}"
      post "/v1/blobs", params: { id: id, data: HELLO }, as: :json, headers: @auth

      assert_response :created
      assert BlobContent.exists?(blob_id: id)
      assert_equal "database", Blob.find_by(blob_id: id).backend
    end

    test "clearing the personal default falls back to the system default" do
      @user.update!(default_backend: "database")

      put "/v1/backends/default", params: { backend: nil }, as: :json, headers: @auth

      assert_response :success
      assert_nil response.parsed_body["user_default"]
      assert_equal "local", response.parsed_body["default"]
    end

    test "rejects defaults that are not available" do
      put "/v1/backends/default", params: { backend: "s3" }, as: :json, headers: @auth
      assert_response :unprocessable_entity

      put "/v1/backends/default", params: { backend: "nope" }, as: :json, headers: @auth
      assert_response :unprocessable_entity
    end

    test "an explicit backend on the request beats the personal default" do
      @user.update!(default_backend: "database")
      id = "explicit-wins-#{SecureRandom.hex(4)}"

      post "/v1/blobs", params: { id: id, data: HELLO, backend: "local" }, as: :json, headers: @auth

      assert_response :created
      assert_equal "local", Blob.find_by(blob_id: id).backend
      assert_not BlobContent.exists?(blob_id: id)
    end
  end
end
