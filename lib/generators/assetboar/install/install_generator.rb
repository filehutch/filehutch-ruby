# frozen_string_literal: true

require "rails/generators"

module Assetboar
  module Generators
    # bin/rails generate assetboar:install
    class InstallGenerator < ::Rails::Generators::Base
      source_root ::File.expand_path("templates", __dir__)

      def create_initializer
        template "initializer.rb", "config/initializers/assetboar.rb"
      end

      def mount_engine
        route 'mount Assetboar::Engine => "/assetboar"'
      end

      def pin_javascript
        return unless ::File.exist?(::File.join(destination_root, "config/importmap.rb"))
        append_to_file "config/importmap.rb", %(pin "assetboar/direct_upload_controller", to: "assetboar/direct_upload_controller.js"\n)
      end

      def show_next_steps
        say ""
        say "AssetBoar installed.", :green
        say "  1. Set ASSETBOAR_API_KEY (Dashboard → API keys) and, if not production, ASSETBOAR_URL."
        say "  2. Add a column and macro:  bin/rails g assetboar:attachment User avatar  then  has_assetboar_file :avatar, policy: \"avatars\""
        say "  3. For browser uploads, set Assetboar.config.authorize_direct_upload in the initializer and register the"
        say "     Stimulus controller:  application.register(\"assetboar-direct-upload\", DirectUploadController)"
      end
    end
  end
end
