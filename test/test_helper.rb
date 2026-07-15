ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"

module ActiveSupport
  class TestCase
    # The suite runs in a single process: several tests deliberately manage
    # process-global seams (storage adapter injection, Net::FTP capture,
    # ENV-driven limits), and at well under a second for the whole run
    # thread-parallelism has nothing to buy — while causing deadlocks once
    # the suite crossed Rails' 50-test parallelization threshold.
    parallelize(workers: 1)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    AUTH_HEADER = { "Authorization" => "Bearer test-token" }.freeze
  end
end
