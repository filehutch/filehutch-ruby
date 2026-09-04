# frozen_string_literal: true

module Assetboar
  # Mount at /assetboar to give browsers a direct-upload endpoint that never
  # exposes the API key:
  #
  #   mount Assetboar::Engine => "/assetboar"
  #
  #   POST /assetboar/uploads              {policy, filename, content_type, byte_size}
  #   POST /assetboar/uploads/:id/complete
  #
  # Both require Assetboar.config.authorize_direct_upload to return true.
  class Engine < ::Rails::Engine
    isolate_namespace Assetboar

    initializer "assetboar.active_record" do
      ActiveSupport.on_load(:active_record) { extend Assetboar::Attachable::ClassMethods }
    end

    initializer "assetboar.assets" do |app|
      app.config.assets.precompile += %w[assetboar/direct_upload_controller.js] if app.config.respond_to?(:assets) && app.config.assets.respond_to?(:precompile)
    end

    initializer "assetboar.logger" do
      Assetboar.config.logger ||= ::Rails.logger
    end
  end
end
