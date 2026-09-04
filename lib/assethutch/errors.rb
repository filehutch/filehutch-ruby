# frozen_string_literal: true

module Assethutch
  class Error < StandardError; end

  # Client-side problems: missing API key, bad arguments.
  class ConfigurationError < Error; end

  # Could not reach AssetHutch or storage (DNS, timeout, TLS, reset).
  class ConnectionError < Error
    attr_reader :cause_error

    def initialize(message, cause_error = nil)
      super(message)
      @cause_error = cause_error
    end
  end

  # AssetHutch answered with {"error": {"code", "message", "details"}}.
  class ApiError < Error
    attr_reader :code, :status, :details

    def initialize(message, code: nil, status: nil, details: nil)
      super(message)
      @code = code&.to_s
      @status = status
      @details = details
    end

    CODE_CLASSES = {
      "unauthorized" => :AuthenticationError,
      "not_found" => :NotFoundError,
      "invalid" => :InvalidRequestError,
      "policy_violation" => :PolicyError,
      "policy_not_found" => :PolicyError,
      "storage_not_ready" => :StorageNotReadyError,
      "invalid_state" => :InvalidStateError,
      "not_ready" => :InvalidStateError,
      "already_deleted" => :InvalidStateError,
      "not_public" => :InvalidStateError,
      "no_public_base_url" => :InvalidStateError,
      "upload_expired" => :UploadError,
      "upload_incomplete" => :UploadError,
      "size_mismatch" => :UploadError,
      "storage_error" => :StorageError,
      "verification_failed" => :StorageError
    }.freeze

    STATUS_CLASSES = { 401 => :AuthenticationError, 403 => :AuthenticationError, 404 => :NotFoundError,
                       409 => :InvalidStateError, 410 => :InvalidStateError, 422 => :InvalidRequestError,
                       429 => :RateLimitError, 502 => :StorageError }.freeze

    # Picks the most specific subclass for an error payload.
    def self.build(status, body)
      error = body.is_a?(Hash) && body["error"].is_a?(Hash) ? body["error"] : {}
      code = error["code"]&.to_s
      message = error["message"] || (status >= 500 ? "AssetHutch returned HTTP #{status}" : "Request failed with HTTP #{status}")
      klass_name = CODE_CLASSES[code] || STATUS_CLASSES[status] || (status >= 500 ? :ServerError : :ApiError)
      Assethutch.const_get(klass_name).new(message, code: code, status: status, details: error["details"])
    end
  end

  class AuthenticationError < ApiError; end
  class NotFoundError < ApiError; end
  class InvalidRequestError < ApiError; end
  class PolicyError < InvalidRequestError; end
  class StorageNotReadyError < ApiError; end
  class InvalidStateError < ApiError; end
  class RateLimitError < ApiError; end
  class ServerError < ApiError; end
  class StorageError < ApiError; end

  # The direct PUT to storage failed, or AssetHutch could not verify it.
  class UploadError < ApiError; end
end
