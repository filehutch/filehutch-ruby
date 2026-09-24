# frozen_string_literal: true

require "rails"
require_relative "rails/attachable"
require_relative "backfill"

module FileHutch
  def self.deprecator = @deprecator ||= ActiveSupport::Deprecation.new("0.3", "file_hutch")
end

require_relative "rails/engine"
