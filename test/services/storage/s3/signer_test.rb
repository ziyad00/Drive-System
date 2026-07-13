require "test_helper"

module Storage
  class S3
    class SignerTest < ActiveSupport::TestCase
      setup do
        @signer = Signer.new(
          region: "us-east-1",
          access_key_id: "AKIAEXAMPLE",
          secret_access_key: "secret"
        )
        @now = Time.utc(2026, 7, 13, 12, 0, 0)
      end

      test "signing is deterministic for identical requests" do
        assert_equal sign_new_request, sign_new_request
      end

      test "signature changes when the payload changes" do
        assert_not_equal sign_new_request(body: "a"), sign_new_request(body: "b")
      end

      test "signature changes when the path changes" do
        assert_not_equal sign_new_request(path: "/bucket/a"), sign_new_request(path: "/bucket/b")
      end

      test "includes the port in the host header for non-default ports" do
        uri = URI("http://minio.test:9000/bucket/key")
        request = Net::HTTP::Get.new(uri)
        @signer.sign!(request, uri, now: @now)

        assert_equal "minio.test:9000", request["host"]
      end

      test "omits the port in the host header for default ports" do
        uri = URI("https://s3.amazonaws.com/bucket/key")
        request = Net::HTTP::Get.new(uri)
        @signer.sign!(request, uri, now: @now)

        assert_equal "s3.amazonaws.com", request["host"]
      end

      test "credential scope is built from date, region and service" do
        uri = URI("https://s3.amazonaws.com/bucket/key")
        request = Net::HTTP::Get.new(uri)
        @signer.sign!(request, uri, now: @now)

        assert_includes request["authorization"], "Credential=AKIAEXAMPLE/20260713/us-east-1/s3/aws4_request"
      end

      private

      def sign_new_request(body: nil, path: "/bucket/key")
        uri = URI("http://minio.test:9000#{path}")
        request = Net::HTTP::Put.new(uri)
        request.body = body
        @signer.sign!(request, uri, now: @now)
        request["authorization"]
      end
    end
  end
end
