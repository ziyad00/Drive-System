require "openssl"

module Storage
  class S3 < Base
    # AWS Signature Version 4 request signing, implemented from the spec:
    # https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-authenticating-requests.html
    #
    # Signing works in three steps:
    #   1. Build a canonical representation of the request and hash it.
    #   2. Wrap that hash in a "string to sign" scoped to date/region/service.
    #   3. HMAC the string with a key derived from the secret through a chain
    #      of date/region/service HMACs, and place the result in the
    #      Authorization header.
    class Signer
      ALGORITHM = "AWS4-HMAC-SHA256"
      SERVICE = "s3"

      def initialize(region:, access_key_id:, secret_access_key:)
        @region = region
        @access_key_id = access_key_id
        @secret_access_key = secret_access_key
      end

      # Adds Host, x-amz-date, x-amz-content-sha256 and Authorization headers
      # to +request+ (a Net::HTTPRequest) in place.
      def sign!(request, uri, now: Time.now.utc)
        timestamp = now.strftime("%Y%m%dT%H%M%SZ")
        date = now.strftime("%Y%m%d")
        payload_hash = sha256_hex(request.body || "")

        request["host"] = host_header(uri)
        request["x-amz-date"] = timestamp
        request["x-amz-content-sha256"] = payload_hash

        canonical_request = build_canonical_request(request, uri, payload_hash)
        string_to_sign = build_string_to_sign(canonical_request, timestamp, date)
        signature = hmac_hex(signing_key(date), string_to_sign)

        request["authorization"] =
          "#{ALGORITHM} Credential=#{@access_key_id}/#{scope(date)}, " \
          "SignedHeaders=#{signed_header_names(request)}, Signature=#{signature}"
      end

      private

      def build_canonical_request(request, uri, payload_hash)
        canonical_headers = signed_headers(request)
          .map { |name, value| "#{name}:#{value}\n" }
          .join

        [
          request.method,
          canonical_uri(uri.path),
          canonical_query(uri.query),
          canonical_headers,
          signed_header_names(request),
          payload_hash
        ].join("\n")
      end

      def build_string_to_sign(canonical_request, timestamp, date)
        [
          ALGORITHM,
          timestamp,
          scope(date),
          sha256_hex(canonical_request)
        ].join("\n")
      end

      # The signing key is the secret run through a chain of HMACs, each step
      # narrowing the key's scope: date -> region -> service -> "aws4_request".
      def signing_key(date)
        key = "AWS4#{@secret_access_key}"
        [date, @region, SERVICE, "aws4_request"].reduce(key) do |k, part|
          hmac(k, part)
        end
      end

      def scope(date)
        "#{date}/#{@region}/#{SERVICE}/aws4_request"
      end

      def signed_headers(request)
        request.each_header
          .map { |name, value| [name.downcase, value.strip] }
          .select { |name, _| name == "host" || name.start_with?("x-amz-") }
          .sort_by(&:first)
      end

      def signed_header_names(request)
        signed_headers(request).map(&:first).join(";")
      end

      # Each path segment is URI-encoded per RFC 3986 (unreserved characters
      # only), while the "/" separators stay literal.
      def canonical_uri(path)
        return "/" if path.blank?

        path.split("/", -1).map { |segment| uri_encode(segment) }.join("/")
      end

      def canonical_query(query)
        return "" if query.blank?

        query.split("&").map { |pair|
          key, value = pair.split("=", 2)
          [uri_encode(key), uri_encode(value || "")]
        }.sort.map { |key, value| "#{key}=#{value}" }.join("&")
      end

      def uri_encode(string)
        string.b.gsub(/[^A-Za-z0-9\-._~]/) { |char| "%%%02X" % char.ord }
      end

      def host_header(uri)
        default_port = uri.scheme == "https" ? 443 : 80
        uri.port == default_port ? uri.host : "#{uri.host}:#{uri.port}"
      end

      def sha256_hex(data)
        OpenSSL::Digest::SHA256.hexdigest(data)
      end

      def hmac(key, data)
        OpenSSL::HMAC.digest("SHA256", key, data)
      end

      def hmac_hex(key, data)
        OpenSSL::HMAC.hexdigest("SHA256", key, data)
      end
    end
  end
end
