# frozen_string_literal: true

module Assethutch
  # Mount at /assethutch to give browsers a direct-upload endpoint that never
  # exposes the API key:
  #
  #   mount Assethutch::Engine => "/assethutch"
  #
  #   POST /assethutch/uploads              {policy, filename, content_type, byte_size}
  #   POST /assethutch/uploads/:id/complete
  #
  # Both require Assethutch.config.authorize_direct_upload to return true.
  class Engine < ::Rails::Engine
    isolate_namespace Assethutch

    initializer "assethutch.active_record" do
      ActiveSupport.on_load(:active_record) { extend Assethutch::Attachable::ClassMethods }
    end

    initializer "assethutch.assets" do |app|
      app.config.assets.precompile += %w[assethutch/direct_upload_controller.js] if app.config.respond_to?(:assets) && app.config.assets.respond_to?(:precompile)
    end

    initializer "assethutch.logger" do
      Assethutch.config.logger ||= ::Rails.logger
    end
  end
end
