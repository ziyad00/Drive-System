# Rejects oversized requests before Rails parses the body, so a huge upload
# costs one header read instead of several gigabytes of JSON/Base64 buffers.
class RequestSizeLimiter
  def initialize(app, max_bytes:)
    @app = app
    @max_bytes = max_bytes
  end

  def call(env)
    if env["CONTENT_LENGTH"].to_i > @max_bytes
      body = { error: "request body too large (limit #{@max_bytes} bytes)" }.to_json
      return [ 413, { "content-type" => "application/json" }, [ body ] ]
    end

    @app.call(env)
  end
end
