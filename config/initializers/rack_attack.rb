# Request throttling. Token entropy already makes brute-force unrealistic
# (~187 bits); this bounds abuse volume — upload spam, auth hammering —
# per client. Pairs with the request-size cap in RequestSizeLimiter.
class Rack::Attack
  # Disabled under test: throttle counters are process-global and would
  # race the parallel test threads.
  Rack::Attack.enabled = !Rails.env.test?

  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

  # One bucket per bearer token (falling back to IP for anonymous
  # requests, which also covers 401 hammering).
  throttle("requests_per_client", limit: proc { Integer(ENV.fetch("RATE_LIMIT_PER_MINUTE", "120")) }, period: 60) do |request|
    request.get_header("HTTP_AUTHORIZATION").presence || request.ip
  end

  Rack::Attack.throttled_responder = lambda do |_request|
    [ 429, { "content-type" => "application/json" },
      [ { error: "rate limit exceeded, retry in a minute" }.to_json ] ]
  end
end
