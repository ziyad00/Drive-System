require "test_helper"

module Storage
  class FtpTest < ActiveSupport::TestCase
    class FakeFtp
      attr_reader :stored

      def binary=(value); end

      def storbinary(command, io, blocksize)
        @stored = [ command, io.read ]
      end
    end

    test "requires a host" do
      assert_raises(Storage::ConfigurationError) { Ftp.new({}) }
    end

    test "connects with TLS by default" do
      options = connect_options_for(Ftp.new(host: "ftp.example.com"))

      assert_equal true, options[:ssl]
    end

    test "plain FTP must be opted into explicitly" do
      options = connect_options_for(Ftp.new(host: "ftp.example.com", tls: "false"))

      assert_not_includes options.keys, :ssl
    end

    test "passes port and credentials through" do
      adapter = Ftp.new(host: "ftp.example.com", port: 2121, user: "u", password: "p")

      options = connect_options_for(adapter)

      assert_equal 2121, options[:port]
      assert_equal "u", options[:username]
      assert_equal "p", options[:password]
    end

    private

    # Captures the options the adapter hands to Net::FTP.open, serving a
    # fake connection instead of dialing anything.
    def connect_options_for(adapter)
      captured = nil
      fake = FakeFtp.new

      Net::FTP.singleton_class.class_eval do
        alias_method :__original_open, :open
        define_method(:open) do |_host, **options, &block|
          captured = options
          block.call(fake)
        end
      end

      adapter.store("some-id", "bytes")
      captured
    ensure
      Net::FTP.singleton_class.class_eval do
        alias_method :open, :__original_open
        remove_method :__original_open
      end
    end
  end
end
