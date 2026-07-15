require "test_helper"

# Rack::Attack itself is disabled in the test environment (its counters are
# process-global and would race the parallel test threads), so these tests
# pin the configuration: the throttle exists, buckets by token then IP, and
# honors the env-configured limit.
class RateLimitingTest < ActiveSupport::TestCase
  test "a per-client throttle is registered" do
    throttle = Rack::Attack.throttles["requests_per_client"]

    assert_not_nil throttle
    assert_equal 60, throttle.period
    assert_equal 120, throttle.limit.call
  end

  test "the limit follows RATE_LIMIT_PER_MINUTE" do
    original = ENV["RATE_LIMIT_PER_MINUTE"]
    ENV["RATE_LIMIT_PER_MINUTE"] = "7"

    assert_equal 7, Rack::Attack.throttles["requests_per_client"].limit.call
  ensure
    original ? ENV["RATE_LIMIT_PER_MINUTE"] = original : ENV.delete("RATE_LIMIT_PER_MINUTE")
  end

  test "requests bucket by bearer token, anonymous requests by IP" do
    throttle = Rack::Attack.throttles["requests_per_client"]

    with_token = Rack::Attack::Request.new(Rack::MockRequest.env_for(
      "/v1/blobs", "HTTP_AUTHORIZATION" => "Bearer abc", "REMOTE_ADDR" => "1.2.3.4"
    ))
    anonymous = Rack::Attack::Request.new(Rack::MockRequest.env_for(
      "/v1/blobs", "REMOTE_ADDR" => "1.2.3.4"
    ))

    assert_equal "Bearer abc", throttle.block.call(with_token)
    assert_equal "1.2.3.4", throttle.block.call(anonymous)
  end
end
