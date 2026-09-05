# frozen_string_literal: true

module FileHutch
  # Verifies the signature FileHutch puts on every webhook delivery:
  #
  #   FileHutch-Signature: t=<unix seconds>,v1=<hex HMAC-SHA256(secret, "<t>.<body>")>
  #
  #   event = FileHutch::Webhook.construct_event(request.raw_post, request.headers["FileHutch-Signature"], secret)
  #   case event["type"]
  #   when "file.created" then Document.find_by(file_hutch_file_id: event["data"]["file"]["id"])&.ready!
  #   end
  module Webhook
    HEADER = "FileHutch-Signature"
    DEFAULT_TOLERANCE = 300

    # Returns the parsed event. Raises SignatureVerificationError if the body was
    # not signed with `secret` in the last `tolerance` seconds.
    def self.construct_event(payload, signature_header, secret, tolerance: DEFAULT_TOLERANCE, now: Time.now)
      verify!(payload, signature_header, secret, tolerance: tolerance, now: now)
      JSON.parse(payload)
    end

    def self.verify!(payload, signature_header, secret, tolerance: DEFAULT_TOLERANCE, now: Time.now)
      raise SignatureVerificationError, "webhook secret is missing" if secret.to_s.empty?

      parts = signature_header.to_s.split(",").filter_map do |part|
        key, value = part.split("=", 2)
        [ key, value ] if value
      end.to_h
      timestamp = parts["t"].to_i
      given = parts["v1"].to_s
      raise SignatureVerificationError, "missing or malformed #{HEADER} header" if timestamp.zero? || given.empty?
      raise SignatureVerificationError, "signature timestamp is outside the #{tolerance}s tolerance" if (now.to_i - timestamp).abs > tolerance

      expected = compute_signature(timestamp, payload, secret)
      raise SignatureVerificationError, "signature does not match" unless secure_compare(expected, given)

      true
    end

    def self.compute_signature(timestamp, payload, secret)
      OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp.to_i}.#{payload}")
    end

    def self.secure_compare(a, b)
      return false unless a.bytesize == b.bytesize

      OpenSSL.fixed_length_secure_compare(a, b)
    end
    private_class_method :secure_compare
  end
end
