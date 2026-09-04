# frozen_string_literal: true

require "json"
require "stringio"
require "openssl"
require "net/http"
require "uri"
require "time"

require_relative "assethutch/version"
require_relative "assethutch/errors"
require_relative "assethutch/configuration"
require_relative "assethutch/resource"
require_relative "assethutch/file"
require_relative "assethutch/upload"
require_relative "assethutch/project"
require_relative "assethutch/client"

# AssetHutch: file infrastructure for apps that aren't Netflix.
#
#   Assethutch.configure { |c| c.api_key = ENV["ASSETHUTCH_API_KEY"] }
#   file = Assethutch.upload("report.pdf", policy: "documents")   # => Assethutch::File (ready)
#   file.signed_url(expires_in: 3600)
#   Assethutch::File.find(file.id).delete
#
# Your application persists `file.id` ("file_…") and nothing else about storage.
module Assethutch
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

    # The shared client built from Assethutch.configuration.
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

require_relative "assethutch/rails" if defined?(::Rails::Railtie)
