# frozen_string_literal: true

require "rails"
require "active_record/railtie"
require "action_controller/railtie"
require "file_hutch"

module Dummy
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f
    config.root = File.expand_path("..", __dir__)
    config.eager_load = false
    config.logger = Logger.new(nil)
    config.active_support.deprecation = :stderr
    config.secret_key_base = "dummy" * 10
    config.hosts.clear
    config.active_record.maintain_test_schema = false
    config.action_controller.allow_forgery_protection = false
    config.active_record.encryption.primary_key = "x" * 32 if config.active_record.respond_to?(:encryption)
  end
end
