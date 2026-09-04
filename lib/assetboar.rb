# frozen_string_literal: true

require "json"
require "stringio"
require "openssl"
require "net/http"
require "uri"
require "time"

require_relative "assetboar/version"
require_relative "assetboar/errors"
require_relative "assetboar/configuration"
require_relative "assetboar/resource"
require_relative "assetboar/file"
require_relative "assetboar/upload"
require_relative "assetboar/project"
require_relative "assetboar/client"

# AssetBoar: file infrastructure for apps that aren't Netflix.
#
#   Assetboar.configure { |c| c.api_key = ENV["ASSETBOAR_API_KEY"] }
#   file = Assetboar.upload("report.pdf", policy: "documents")   # => Assetboar::File (ready)
#   file.signed_url(expires_in: 3600)
#   Assetboar::File.find(file.id).delete
#
# Your application persists `file.id` ("file_…") and nothing else about storage.
module Assetboar
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

    # The shared client built from Assetboar.configuration.
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

require_relative "assetboar/rails" if defined?(::Rails::Railtie)
