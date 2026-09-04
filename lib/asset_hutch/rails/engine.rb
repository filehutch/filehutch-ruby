# frozen_string_literal: true

module AssetHutch
  # Mount at /asset_hutch to give browsers a direct-upload endpoint that never
  # exposes the API key:
  #
  #   mount AssetHutch::Engine => "/asset_hutch"
  #
  #   POST /asset_hutch/uploads              {policy, filename, content_type, byte_size}
  #   POST /asset_hutch/uploads/:id/complete
  #
  # Both require AssetHutch.config.authorize_direct_upload to return true.
  class Engine < ::Rails::Engine
    isolate_namespace AssetHutch

    initializer "asset_hutch.active_record" do
      ActiveSupport.on_load(:active_record) { extend AssetHutch::Attachable::ClassMethods }
    end

    initializer "asset_hutch.assets" do |app|
      app.config.assets.precompile += %w[asset_hutch/direct_upload_controller.js] if app.config.respond_to?(:assets) && app.config.assets.respond_to?(:precompile)
    end

    initializer "asset_hutch.logger" do
      AssetHutch.config.logger ||= ::Rails.logger
    end
  end
end
