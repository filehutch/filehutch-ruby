# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
ENV["FILE_HUTCH_API_KEY"] = "fh_testTESTtestTESTtestTESTtestTESTtestTEST"
ENV["FILE_HUTCH_URL"] = "https://file_hutch.test"

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
      FileHutch.instance_variable_set(:@configuration, nil)
      FileHutch.reset_client!
      FileHutch::Attachable.reset_policies!
      FileHutch.config.authorize_direct_upload = nil
    end
  end
end
