require "test_helper"

class IdentityTest < ActionDispatch::IntegrationTest
  setup do
    @alice, alice_token = ApiUser.generate!(name: "alice-#{SecureRandom.hex(4)}")
    @bob, bob_token = ApiUser.generate!(name: "bob-#{SecureRandom.hex(4)}")
    @alice_auth = { "Authorization" => "Bearer #{alice_token}" }
    @bob_auth = { "Authorization" => "Bearer #{bob_token}" }
  end

  # Real public keys, as a client would generate and publish them.
  def keypair
    kem = OpenSSL::PKey.generate_key("X25519").public_to_der
    sig = OpenSSL::PKey.generate_key("ED25519").public_to_der
    { kem_public_key: Base64.strict_encode64(kem), sig_public_key: Base64.strict_encode64(sig) }
  end

  test "identity endpoints require authentication" do
    get "/v1/identity"
    assert_response :unauthorized
  end

  test "publishing identity keys and looking them up" do
    keys = keypair
    put "/v1/identity", params: keys, as: :json, headers: @alice_auth
    assert_response :success
    assert_equal keys[:kem_public_key], response.parsed_body["kem_public_key"]
    assert response.parsed_body["fingerprint"].present?

    get "/v1/users/#{@alice.name}/identity", headers: @bob_auth
    assert_response :success
    assert_equal keys[:sig_public_key], response.parsed_body["sig_public_key"]
    assert_equal @alice.name, response.parsed_body["user"]
  end

  test "the server only ever stores public key material" do
    put "/v1/identity", params: keypair, as: :json, headers: @alice_auth
    identity = @alice.reload.user_identity
    # Public keys deserialize without a private component.
    key = OpenSSL::PKey.read(Base64.decode64(identity.kem_public_key))
    assert_raises(OpenSSL::PKey::PKeyError) { key.raw_private_key }
  end

  test "rotating keys appends to the transparency log and the chain verifies" do
    put "/v1/identity", params: keypair, as: :json, headers: @alice_auth
    put "/v1/identity", params: keypair, as: :json, headers: @bob_auth
    rotated = keypair
    put "/v1/identity", params: rotated, as: :json, headers: @alice_auth # alice rotates

    get "/v1/keylog", headers: @alice_auth
    assert_response :success
    body = response.parsed_body
    assert_equal 3, body["head_seq"]
    assert_equal true, body["chain_valid"]
    assert_equal (1..3).to_a, body["entries"].map { |e| e["seq"] }
    # Alice's latest published key is her rotated one.
    assert_equal rotated[:kem_public_key], body["entries"].last["kem_public_key"]
  end

  test "tampering with a past log entry breaks verification" do
    put "/v1/identity", params: keypair, as: :json, headers: @alice_auth
    put "/v1/identity", params: keypair, as: :json, headers: @bob_auth

    KeyLogEntry.order(:seq).first.update_column(:kem_public_key, "forged-key")
    assert_equal false, KeyLogEntry.verify_chain
  end

  test "fingerprints let two users confirm the same keys" do
    keys = keypair
    put "/v1/identity", params: keys, as: :json, headers: @alice_auth

    get "/v1/identity", headers: @alice_auth
    alice_view = response.parsed_body["fingerprint"]
    get "/v1/users/#{@alice.name}/identity", headers: @bob_auth
    bob_view = response.parsed_body["fingerprint"]

    assert_equal alice_view, bob_view
  end
end
