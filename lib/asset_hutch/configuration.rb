# frozen_string_literal: true

module AssetHutch
  # Global settings. Every value can come from the environment so a deploy
  # (or an AI agent) can configure the gem without touching Ruby.
  class Configuration
    DEFAULT_URL = "https://api.assethutch.com"

    attr_accessor :api_key, :url, :open_timeout, :read_timeout, :write_timeout, :logger, :user_agent

    # Rails direct uploads (see AssetHutch::Engine).
    #   authorize_direct_upload = ->(controller, policy) { controller.current_user.present? }
    attr_accessor :authorize_direct_upload, :direct_upload_parent_controller

    def initialize
      @api_key = ENV["ASSETHUTCH_API_KEY"]
      @url = ENV.fetch("ASSETHUTCH_URL", DEFAULT_URL)
      @open_timeout = 5
      @read_timeout = 30
      @write_timeout = 120
      @logger = nil
      @user_agent = "assethutch-ruby/#{VERSION} ruby/#{RUBY_VERSION}"
      @authorize_direct_upload = nil
      @direct_upload_parent_controller = "ApplicationController"
    end

    def validate!
      raise ConfigurationError, "AssetHutch.config.api_key is missing (set ASSETHUTCH_API_KEY)" if api_key.nil? || api_key.to_s.strip.empty?
      raise ConfigurationError, "AssetHutch.config.url is missing (set ASSETHUTCH_URL)" if url.nil? || url.to_s.strip.empty?
      self
    end
  end
end
