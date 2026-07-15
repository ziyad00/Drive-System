require "net/http"

# Thin client for the OpenBao (Vault-compatible) transit engine — the KMS
# that wraps and unwraps data keys under a named master key (KEK). Only
# wrapped keys ever leave here; the KEK never does. Rotating the KEK version
# and rewrapping keeps stored data untouched (envelope rotation).
module Kms
  class Error < StandardError; end

  class << self
    def enabled?
      config[:addr].present? && config[:token].present?
    end

    # Seals plaintext bytes (a DEK) → an opaque "vault:v1:..." token.
    def wrap(plaintext)
      body = transit("encrypt", plaintext: Base64.strict_encode64(plaintext))
      body.dig("data", "ciphertext") or raise Error, "no ciphertext in KMS response"
    end

    # Reverses wrap.
    def unwrap(ciphertext)
      body = transit("decrypt", ciphertext: ciphertext)
      encoded = body.dig("data", "plaintext") or raise Error, "no plaintext in KMS response"
      Base64.decode64(encoded)
    end

    # Re-seals a wrapped key under the KEK's latest version without exposing
    # the key — the core of zero-data-movement rotation.
    def rewrap(ciphertext)
      body = transit("rewrap", ciphertext: ciphertext)
      body.dig("data", "ciphertext") or raise Error, "no ciphertext in KMS response"
    end

    def config
      Rails.application.config_for(:simple_drive).fetch(:kms, {})
    end

    private

    def transit(operation, payload)
      uri = URI.join(config[:addr], "/v1/transit/#{operation}/#{config[:key]}")
      request = Net::HTTP::Post.new(uri)
      request["X-Vault-Token"] = config[:token]
      request["Content-Type"] = "application/json"
      request.body = payload.to_json

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                 open_timeout: 3, read_timeout: 10) { |http| http.request(request) }
      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "KMS #{operation} failed: #{response.code} #{response.body&.truncate(200)}"
      end

      JSON.parse(response.body)
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError => error
      raise Error, "KMS unreachable: #{error.message}"
    end
  end
end
