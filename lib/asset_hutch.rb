# frozen_string_literal: true

require "json"
require "stringio"
require "openssl"
require "net/http"
require "uri"
require "time"

require_relative "asset_hutch/version"
require_relative "asset_hutch/errors"
require_relative "asset_hutch/configuration"
require_relative "asset_hutch/resource"
require_relative "asset_hutch/file"
require_relative "asset_hutch/upload"
require_relative "asset_hutch/project"
require_relative "asset_hutch/client"

# AssetHutch: file infrastructure for apps that aren't Netflix.
#
#   AssetHutch.configure { |c| c.api_key = ENV["ASSET_HUTCH_API_KEY"] }
#   file = AssetHutch.upload("report.pdf", policy: "documents")   # => AssetHutch::File (ready)
#   file.signed_url(expires_in: 3600)
#   AssetHutch::File.find(file.id).delete
#
# Your application persists `file.id` ("file_…") and nothing else about storage.
module AssetHutch
  class << self
    def configuration
      @configuration ||= Configuration.new
    end
    alias config configuration

    def configure
      yield configuration
      reset_client!
      configuration
    end

    # The shared client built from AssetHutch.configuration.
    def client
      @client ||= Client.new(configuration)
    end

    def client=(client)
      @client = client
    end

    def reset_client!
      @client = nil
    end

    # Convenience delegators for one-project apps.
    def upload(source, **options) = client.upload(source, **options)
    def file(id) = client.file(id)
    def project = client.project
  end
end

require_relative "asset_hutch/rails" if defined?(::Rails::Railtie)
