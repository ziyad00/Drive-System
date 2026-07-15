require "net/ftp"

module Storage
  # Bonus backend: stores blobs on an FTP server. Files are named by the
  # SHA-256 of the blob id inside a configurable base directory.
  #
  # Connections use FTPS (explicit TLS) by default so credentials and blob
  # bytes never cross the network in cleartext; plain FTP must be opted
  # into for servers that cannot speak TLS.
  class Ftp < Base
    def initialize(config = {})
      super

      @host = config[:host].presence or
        raise ConfigurationError, "ftp backend requires a host"
      @port = config.fetch(:port, 21).to_i
      @user = config[:user]
      @password = config[:password]
      @base_dir = config[:base_dir].presence
      @tls = ActiveModel::Type::Boolean.new.cast(config.fetch(:tls, true))
    end

    def store(id, data)
      connect do |ftp|
        ftp.storbinary("STOR #{key_for(id)}", StringIO.new(data), Net::FTP::DEFAULT_BLOCKSIZE)
      end
    end

    def retrieve(id)
      connect do |ftp|
        buffer = +""
        ftp.retrbinary("RETR #{key_for(id)}", Net::FTP::DEFAULT_BLOCKSIZE) { |chunk| buffer << chunk }
        buffer
      end
    rescue Net::FTPPermError
      raise NotFound, "no FTP file for blob #{id.inspect}"
    end

    private

    def connect
      options = { port: @port, username: @user, password: @password }
      options[:ssl] = true if @tls

      Net::FTP.open(@host, **options) do |ftp|
        ftp.binary = true
        if @base_dir
          ensure_base_dir(ftp)
          ftp.chdir(@base_dir)
        end
        yield ftp
      end
    end

    def ensure_base_dir(ftp)
      ftp.mkdir(@base_dir)
    rescue Net::FTPPermError
      # already exists
    end
  end
end
