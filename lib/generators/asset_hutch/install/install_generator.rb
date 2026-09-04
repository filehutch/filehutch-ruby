# frozen_string_literal: true

require "rails/generators"

module AssetHutch
  module Generators
    # bin/rails generate asset_hutch:install
    class InstallGenerator < ::Rails::Generators::Base
      source_root ::File.expand_path("templates", __dir__)

      def create_initializer
        template "initializer.rb", "config/initializers/asset_hutch.rb"
      end

      def mount_engine
        route 'mount AssetHutch::Engine => "/asset_hutch"'
      end

      def pin_javascript
        return unless ::File.exist?(::File.join(destination_root, "config/importmap.rb"))
        append_to_file "config/importmap.rb", %(pin "asset_hutch/direct_upload_controller", to: "asset_hutch/direct_upload_controller.js"\n)
      end

      def show_next_steps
        say ""
        say "AssetHutch installed.", :green
        say "  1. Set ASSET_HUTCH_API_KEY (Dashboard → API keys) and, if not production, ASSET_HUTCH_URL."
        say "  2. Add a column and macro:  bin/rails g asset_hutch:attachment User avatar  then  has_asset_hutch_file :avatar, policy: \"avatars\""
        say "  3. For browser uploads, set AssetHutch.config.authorize_direct_upload in the initializer and register the"
        say "     Stimulus controller:  application.register(\"asset-hutch-direct-upload\", DirectUploadController)"
      end
    end
  end
end
