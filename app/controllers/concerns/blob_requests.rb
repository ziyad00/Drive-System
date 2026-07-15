# Shared request plumbing for endpoints that accept or serve blob content:
# Base64 handling, size enforcement, and the error-to-status mapping.
module BlobRequests
  extend ActiveSupport::Concern

  class InvalidBase64 < StandardError; end

  included do
    # rescue_from dispatches in reverse registration order, so the generic
    # Storage::Error handler is registered before its NotFound subclass.
    rescue_from Storage::Error do |error|
      render json: { error: "storage backend failure: #{error.message}" }, status: :bad_gateway
    end

    rescue_from Storage::NotFound do
      render json: { error: "blob content not found in storage backend" }, status: :not_found
    end

    rescue_from Storage::UnusableBackend do |error|
      render json: { error: error.message }, status: :unprocessable_entity
    end

    rescue_from InvalidBase64 do
      render json: { error: "data is not valid Base64" }, status: :unprocessable_entity
    end

    rescue_from ActionController::ParameterMissing do |error|
      render json: { error: "missing required field: #{error.param}" }, status: :bad_request
    end

    # Losing a duplicate race at the database index (both requests passed
    # validation) is the same client error as any duplicate.
    rescue_from ActiveRecord::RecordNotUnique do
      render json: { error: "already exists" }, status: :conflict
    end

    rescue_from ActiveRecord::RecordInvalid do |error|
      if error.record.errors.of_kind?(:blob_id, :taken) || error.record.errors.of_kind?(:name, :taken)
        render json: { error: "#{error.record.class.name.downcase} already exists" }, status: :conflict
      else
        render json: { error: error.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end
    end
  end

  private

  def decode_base64!(value)
    Base64.strict_decode64(value.to_s)
  rescue ArgumentError
    raise InvalidBase64
  end

  # Renders 413 and returns false when the payload is over the limit.
  def enforce_blob_size!(data)
    max = Storage.config.fetch(:max_blob_bytes)
    return true if data.bytesize <= max

    render json: { error: "blob exceeds the maximum size of #{max} bytes" },
           status: :content_too_large
    false
  end
end
