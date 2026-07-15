require "test_helper"

module Storage
  class S3Test < ActiveSupport::TestCase
    setup do
      @adapter = S3.new(
        endpoint: "http://minio.test:9000",
        bucket: "blobs",
        region: "us-east-1",
        access_key_id: "AKIAEXAMPLE",
        secret_access_key: "secret"
      )
      @key = Digest::SHA256.hexdigest("my-id")
    end

    test "uploads with a path-style URL and a SigV4 authorization header" do
      signed = nil
      stub_request(:put, "http://minio.test:9000/blobs/#{@key}")
        .with(body: "payload") { |req| signed = req.headers }
        .to_return(status: 200)

      @adapter.store("my-id", "payload")

      assert_match(
        %r{\AAWS4-HMAC-SHA256\sCredential=AKIAEXAMPLE/\d{8}/us-east-1/s3/aws4_request,
           \sSignedHeaders=host;x-amz-content-sha256;x-amz-date,\sSignature=\h{64}\z}x,
        signed["Authorization"]
      )
      assert_equal OpenSSL::Digest::SHA256.hexdigest("payload"), signed["X-Amz-Content-Sha256"]
      assert_match(/\A\d{8}T\d{6}Z\z/, signed["X-Amz-Date"])
    end

    test "downloads the stored object" do
      stub_request(:get, "http://minio.test:9000/blobs/#{@key}")
        .to_return(status: 200, body: "payload")

      assert_equal "payload", @adapter.retrieve("my-id")
    end

    test "raises NotFound when the object does not exist" do
      stub_request(:get, "http://minio.test:9000/blobs/#{@key}").to_return(status: 404)

      assert_raises(Storage::NotFound) { @adapter.retrieve("my-id") }
    end

    test "raises Error on other failures" do
      stub_request(:put, "http://minio.test:9000/blobs/#{@key}").to_return(status: 403, body: "denied")

      assert_raises(Storage::Error) { @adapter.store("my-id", "payload") }
    end

    test "maps timeouts to Storage::Error" do
      stub_request(:get, "http://minio.test:9000/blobs/#{@key}").to_timeout

      error = assert_raises(Storage::Error) { @adapter.retrieve("my-id") }
      assert_match(/timed out|failed/, error.message)
    end

    test "maps connection failures to Storage::Error" do
      stub_request(:put, "http://minio.test:9000/blobs/#{@key}")
        .to_raise(Errno::ECONNREFUSED)

      assert_raises(Storage::Error) { @adapter.store("my-id", "payload") }
    end

    test "requires full configuration" do
      assert_raises(Storage::ConfigurationError) { S3.new(endpoint: "http://x", bucket: "b") }
    end
  end
end
