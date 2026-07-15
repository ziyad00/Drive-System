require "test_helper"
require "support/fake_kms"

class SseTest < ActionDispatch::IntegrationTest
  setup do
    _u, token = ApiUser.generate!(name: "sse-#{SecureRandom.hex(4)}")
    @auth = { "Authorization" => "Bearer #{token}" }
    FakeKms.install!
  end

  teardown { FakeKms.uninstall! }

  test "stored bytes are ciphertext but reads return plaintext" do
    post "/v1/files", params: { path: "/secret.txt", data: Base64.strict_encode64("top secret") },
         as: :json, headers: @auth
    assert_response :created

    blob = Node.find(response.parsed_body["id"]).blob
    assert_equal "sse", blob.encryption
    assert blob.wrapped_dek.present?

    raw = Storage.backend(blob.backend).retrieve(blob.storage_id)
    assert_not_includes raw, "top secret"

    get "/v1/fs/secret.txt", headers: @auth
    assert_equal Base64.strict_encode64("top secret"), response.parsed_body["data"]
  end

  test "encrypted content survives a download with range requests" do
    body = ("ABCDEFGHIJ" * 5000).b
    post "/v1/files", params: { path: "/big.bin", data: Base64.strict_encode64(body) },
         as: :json, headers: @auth

    get "/v1/dl/big.bin", headers: @auth.merge("Range" => "bytes=0-9")
    assert_response :partial_content
    assert_equal body.byteslice(0, 10), response.body
  end
end
