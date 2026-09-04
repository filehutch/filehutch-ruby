# frozen_string_literal: true

module Assetboar
  # A stored file. `id` ("file_…") is the only thing your app should persist.
  class File < Resource
    ID_PATTERN = /\Afile_[0-9A-Za-z]{20}\z/
    STATUSES = %w[pending ready failed deleted].freeze

    attribute :filename, :content_type, :byte_size, :checksum, :visibility, :status, :metadata,
              :policy, :storage_connection_id, :url
    time_attribute :created_at, :updated_at

    def self.id?(value) = value.is_a?(String) && value.match?(ID_PATTERN)

    def self.find(id, client: Assetboar.client) = client.file(id)

    STATUSES.each { |s| define_method(:"#{s}?") { status == s } }

    def public? = visibility == "public"
    def private? = visibility == "private"
    def image? = content_type.to_s.start_with?("image/")
    def pdf? = content_type == "application/pdf"
    def metadata = self["metadata"] || {}

    # Short-lived URL that works for private and public files alike.
    def signed_url(expires_in: nil, disposition: nil)
      client!.signed_url(id, expires_in: expires_in, disposition: disposition).url
    end

    # Public URL when the file is public and ready, otherwise a signed URL.
    def url_or_signed_url(expires_in: nil, disposition: nil)
      url || signed_url(expires_in: expires_in, disposition: disposition)
    end

    def reload = client!.file(id)

    # Deletes the bytes; the id keeps resolving with status "deleted".
    def delete
      client!.delete_file(id)
      reload
    end
  end

  SignedUrl = Struct.new(:url, :expires_at, keyword_init: true) do
    def to_s = url
  end
end
