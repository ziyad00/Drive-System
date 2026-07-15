require "test_helper"

module V1
  class DownloadsTest < ActionDispatch::IntegrationTest
    CONTENT = "0123456789abcdefghij" # 20 bytes

    setup do
      @user, token = ApiUser.generate!(name: "dl-user-#{SecureRandom.hex(4)}")
      @auth = { "Authorization" => "Bearer #{token}" }

      post "/v1/files", params: { path: "/data.bin", data: Base64.strict_encode64(CONTENT) },
           as: :json, headers: @auth
      @etag = response.headers["ETag"]
    end

    test "serves the full body with type, ETag and Accept-Ranges" do
      get "/v1/dl/data.bin", headers: @auth

      assert_response :ok
      assert_equal CONTENT, response.body
      assert_equal "bytes", response.headers["Accept-Ranges"]
      assert_equal @etag, response.headers["ETag"]
    end

    test "serves a bounded range as 206 with Content-Range" do
      get "/v1/dl/data.bin", headers: @auth.merge("Range" => "bytes=0-9")

      assert_response :partial_content
      assert_equal "0123456789", response.body
      assert_equal "bytes 0-9/20", response.headers["Content-Range"]
    end

    test "serves open-ended and suffix ranges" do
      get "/v1/dl/data.bin", headers: @auth.merge("Range" => "bytes=15-")
      assert_response :partial_content
      assert_equal "fghij", response.body

      get "/v1/dl/data.bin", headers: @auth.merge("Range" => "bytes=-5")
      assert_response :partial_content
      assert_equal "fghij", response.body
      assert_equal "bytes 15-19/20", response.headers["Content-Range"]
    end

    test "clamps ranges past the end and rejects unsatisfiable ones" do
      get "/v1/dl/data.bin", headers: @auth.merge("Range" => "bytes=10-9999")
      assert_response :partial_content
      assert_equal "abcdefghij", response.body

      get "/v1/dl/data.bin", headers: @auth.merge("Range" => "bytes=99-")
      assert_response :range_not_satisfiable
      assert_equal "bytes */20", response.headers["Content-Range"]
    end

    test "ignores malformed range headers" do
      get "/v1/dl/data.bin", headers: @auth.merge("Range" => "bytes=nope")

      assert_response :ok
      assert_equal CONTENT, response.body
    end

    test "If-Range with a stale ETag falls back to the full body" do
      get "/v1/dl/data.bin", headers: @auth.merge("Range" => "bytes=0-9", "If-Range" => '"stale"')
      assert_response :ok
      assert_equal CONTENT, response.body

      get "/v1/dl/data.bin", headers: @auth.merge("Range" => "bytes=0-9", "If-Range" => @etag)
      assert_response :partial_content
    end

    test "folders and unknown paths do not download" do
      get "/v1/dl/nope.bin", headers: @auth
      assert_response :not_found

      post "/v1/folders", params: { path: "/dir" }, as: :json, headers: @auth
      get "/v1/dl/dir", headers: @auth
      assert_response :bad_request
    end

    test "requires authentication" do
      get "/v1/dl/data.bin"

      assert_response :unauthorized
    end
  end
end
