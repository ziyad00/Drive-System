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
      @open_timeout = config.fetch(:open_timeout, 5).to_f
      @read_timeout = config.fetch(:read_timeout, 30).to_f
      @write_timeout = config.fetch(:write_timeout, 30).to_f
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

    # Every request runs under explicit timeouts so a stalled endpoint
    # fails fast instead of pinning a server thread for Net::HTTP's
    # 60-second defaults, and network failures surface as Storage::Error.
    def request(verb, key, body: nil)
      uri = @endpoint.dup
      uri.path = "/#{@bucket}/#{key}"

      request = verb.new(uri)
      request.body = body
      @signer.sign!(request, uri)

      Net::HTTP.start(uri.host, uri.port,
                      use_ssl: uri.scheme == "https",
                      open_timeout: @open_timeout,
                      read_timeout: @read_timeout,
                      write_timeout: @write_timeout) do |http|
        http.request(request)
      end
    rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout => error
      raise Error, "S3 request timed out: #{error.class.name.demodulize}"
    rescue SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError => error
      raise Error, "S3 request failed: #{error.message}"
    end
  end
end
