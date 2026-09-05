# frozen_string_literal: true

module FileHutch
  # Direct-upload instructions from POST /api/v1/uploads plus the pending file.
  class Upload < Resource
    attribute :file_id, :method, :url, :headers
    time_attribute :expires_at

    def initialize(attributes, file: nil, client: nil)
      super(attributes, client: client)
      @file = file
    end

    attr_reader :file

    def headers = self["headers"] || {}
    def expired? = expires_at && expires_at <= Time.now

    # PUTs the bytes straight to storage. `source` is an IO or a String of bytes.
    def put(source)
      client!.put_to_storage(self, source)
      self
    end

    # Tells FileHutch the bytes are in place; returns the ready file.
    def complete = client!.complete_upload(id)
  end
end
