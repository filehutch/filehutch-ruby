# frozen_string_literal: true

module FileHutch
  # Mount at /file_hutch to give browsers a direct-upload endpoint that never
  # exposes the API key:
  #
  #   mount FileHutch::Engine => "/file_hutch"
  #
  #   POST /file_hutch/uploads              {policy, filename, content_type, byte_size}
  #   POST /file_hutch/uploads/:id/complete
  #
  # Both require FileHutch.config.authorize_direct_upload to return true.
  class Engine < ::Rails::Engine
    isolate_namespace FileHutch

    initializer "file_hutch.active_record" do
      ActiveSupport.on_load(:active_record) { extend FileHutch::Attachable::ClassMethods }
    end

    initializer "file_hutch.assets" do |app|
      app.config.assets.precompile += %w[file_hutch/direct_upload_controller.js] if app.config.respond_to?(:assets) && app.config.assets.respond_to?(:precompile)
    end

    initializer "file_hutch.logger" do
      FileHutch.config.logger ||= ::Rails.logger
    end
  end
end
