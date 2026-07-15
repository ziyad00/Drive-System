require "test_helper"
require "support/fake_kms"

class EnvelopeTest < ActiveSupport::TestCase
  setup { FakeKms.install! }
  teardown { FakeKms.uninstall! }

  test "round-trips content across chunk boundaries" do
    [ "", "small", "x" * Envelope::CHUNK, "y" * (Envelope::CHUNK * 3 + 17), Random.bytes(200_000) ].each do |data|
      ciphertext, wrapped = Envelope.seal(data)
      assert_not_equal data, ciphertext.byteslice(8..) if data.bytesize > 0
      assert_equal data.b, Envelope.open(ciphertext, wrapped)
    end
  end

  test "each seal uses a fresh data key and nonce" do
    a, = Envelope.seal("same")
    b, = Envelope.seal("same")
    assert_not_equal a, b
  end

  test "tampering with a chunk is detected" do
    ciphertext, wrapped = Envelope.seal("authentic content here")
    tampered = ciphertext.dup
    tampered.setbyte(tampered.bytesize - 1, tampered.getbyte(tampered.bytesize - 1) ^ 0x01)

    assert_raises(Storage::Error) { Envelope.open(tampered, wrapped) }
  end

  test "truncating chunks is detected via the final-chunk flag" do
    data = "z" * (Envelope::CHUNK * 2)
    ciphertext, wrapped = Envelope.seal(data)
    # Drop the last chunk (length header + payload) by cutting the body.
    prefix = ciphertext.byteslice(0, 4 + Envelope::NONCE_PREFIX)
    body = ciphertext.byteslice(4 + Envelope::NONCE_PREFIX..)
    first_len = body.byteslice(0, 8).unpack1("Q>")
    truncated = prefix + body.byteslice(0, 8 + first_len)

    assert_raises(Storage::Error) { Envelope.open(truncated, wrapped) }
  end
end
