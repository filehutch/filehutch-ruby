# frozen_string_literal: true

require "json"
require "stringio"
require "openssl"
require "net/http"
require "uri"
require "time"

require_relative "file_hutch/version"
require_relative "file_hutch/errors"
require_relative "file_hutch/configuration"
require_relative "file_hutch/resource"
require_relative "file_hutch/file"
require_relative "file_hutch/upload"
require_relative "file_hutch/project"
require_relative "file_hutch/client"
require_relative "file_hutch/webhook"
require_relative "file_hutch/cli"

# FileHutch: file infrastructure for apps that aren't Netflix.
#
#   FileHutch.configure { |c| c.api_key = ENV["FILE_HUTCH_API_KEY"] }
#   file = FileHutch.upload("report.pdf", policy: "documents")   # => FileHutch::File (ready)
#   file.signed_url(expires_in: 3600)
#   FileHutch::File.find(file.id).delete
#
# Your application persists `file.id` ("file_…") and nothing else about storage.
module FileHutch
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

    # The shared client built from FileHutch.configuration.
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

require_relative "file_hutch/rails" if defined?(::Rails::Railtie)
