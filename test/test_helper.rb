# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
ENV["ASSETHUTCH_API_KEY"] = "ah_testTESTtestTESTtestTESTtestTESTtestTEST"
ENV["ASSETHUTCH_URL"] = "https://assethutch.test"

require_relative "dummy/config/application"
Rails.application.initialize!

require "rails/test_help"
ActiveRecord::Schema.verbose = false
load File.expand_path("dummy/db/schema.rb", __dir__)
require "minitest/autorun"
require "webmock/minitest"
require_relative "support/api_stubs"

module ActiveSupport
  class TestCase
    include ApiStubs
    self.file_fixture_path = File.expand_path("fixtures/files", __dir__)

    setup do
      Assethutch.instance_variable_set(:@configuration, nil)
      Assethutch.reset_client!
      Assethutch::Attachable.reset_policies!
      Assethutch.config.authorize_direct_upload = nil
    end
  end
end
