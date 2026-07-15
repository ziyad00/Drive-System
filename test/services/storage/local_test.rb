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

    test "leaves no temp files behind after a successful store" do
      @adapter.store("clean", "payload")

      leftovers = Dir.glob(File.join(@root, "**", "*.tmp-*"))
      assert_empty leftovers
    end

    test "overwrites an existing file atomically" do
      @adapter.store("rewrite", "first")
      @adapter.store("rewrite", "second")

      assert_equal "second", @adapter.retrieve("rewrite")
    end

    test "raises NotFound for unknown ids" do
      assert_raises(Storage::NotFound) { @adapter.retrieve("missing") }
    end

    test "requires a path" do
      assert_raises(Storage::ConfigurationError) { Local.new({}) }
    end
  end
end
