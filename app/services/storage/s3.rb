require "net/http"

module Storage
  # Talks to any S3-compatible service (AWS S3, MinIO, DigitalOcean Spaces...)
  # using nothing but Net::HTTP and a hand-rolled AWS Signature Version 4
  # implementation (see Storage::S3::Signer) — no S3 SDK involved.
  #
  # Objects are addressed path-style ({endpoint}/{bucket}/{key}) so that
  # non-AWS implementations like MinIO work out of the box.
  class S3 < Base
    def initialize(config = {})
      super

      %i[endpoint bucket region access_key_id secret_access_key].each do |key|
        config[key].present? or
          raise ConfigurationError, "s3 backend requires #{key}"
      end

      @endpoint = URI(config[:endpoint])
      @bucket = config[:bucket]
      @signer = Signer.new(
        region: config[:region],
        access_key_id: config[:access_key_id],
        secret_access_key: config[:secret_access_key]
      )
    end

    def store(id, data)
      response = request(Net::HTTP::Put, key_for(id), body: data)
      return if response.is_a?(Net::HTTPSuccess)

      raise Error, "S3 upload failed: #{response.code} #{response.message} — #{response.body&.truncate(200)}"
    end

    def retrieve(id)
      response = request(Net::HTTP::Get, key_for(id))

      case response
      when Net::HTTPSuccess then response.body
      when Net::HTTPNotFound then raise NotFound, "no S3 object for blob #{id.inspect}"
      else
        raise Error, "S3 download failed: #{response.code} #{response.message} — #{response.body&.truncate(200)}"
      end
    end

    private

    def request(verb, key, body: nil)
      uri = @endpoint.dup
      uri.path = "/#{@bucket}/#{key}"

      request = verb.new(uri)
      request.body = body
      @signer.sign!(request, uri)

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(request)
      end
    end
  end
end
