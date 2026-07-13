require "test_helper"

module Storage
  class DatabaseTest < ActiveSupport::TestCase
    setup do
      @adapter = Database.new
    end

    test "round-trips binary data through the blob_contents table" do
      data = Random.bytes(64)
      id = "db-blob-#{SecureRandom.hex(4)}"

      @adapter.store(id, data)

      assert_equal data, @adapter.retrieve(id)
      assert BlobContent.exists?(blob_id: id)
    end

    test "raises NotFound for unknown ids" do
      assert_raises(Storage::NotFound) { @adapter.retrieve("missing") }
    end
  end
end
