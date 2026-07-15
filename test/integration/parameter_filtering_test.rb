require "test_helper"

class ParameterFilteringTest < ActiveSupport::TestCase
  test "blob payload parameters are filtered from logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    filtered = filter.filter(data: "SGVsbG8=", payload: "bytes", id: "my-blob")

    assert_equal "[FILTERED]", filtered[:data]
    assert_equal "[FILTERED]", filtered[:payload]
    assert_equal "my-blob", filtered[:id]
  end
end
