require "test_helper"

module Storage
  class LocalTest < ActiveSupport::TestCase
    setup do
      @root = Rails.root.join("tmp", "test_storage_unit").to_s
      @adapter = Local.new(path: @root)
    end

    teardown do
      FileUtils.rm_rf(@root)
    end

    test "round-trips binary data" do
      data = Random.bytes(64)
      @adapter.store("some/id", data)

      assert_equal data, @adapter.retrieve("some/id")
    end

    test "shards files into subdirectories named by the id hash" do
      @adapter.store("abc", "payload")

      key = Digest::SHA256.hexdigest("abc")
      assert File.file?(File.join(@root, key[0, 2], key[2, 2], key))
    end

    test "raises NotFound for unknown ids" do
      assert_raises(Storage::NotFound) { @adapter.retrieve("missing") }
    end

    test "requires a path" do
      assert_raises(Storage::ConfigurationError) { Local.new({}) }
    end
  end
end
