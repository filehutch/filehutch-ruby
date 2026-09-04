# frozen_string_literal: true

require "rails/generators"

module Assethutch
  module Generators
    # bin/rails generate assethutch:install
    class InstallGenerator < ::Rails::Generators::Base
      source_root ::File.expand_path("templates", __dir__)

      def create_initializer
        template "initializer.rb", "config/initializers/assethutch.rb"
      end

      def mount_engine
        route 'mount Assethutch::Engine => "/assethutch"'
      end

      def pin_javascript
        return unless ::File.exist?(::File.join(destination_root, "config/importmap.rb"))
        append_to_file "config/importmap.rb", %(pin "assethutch/direct_upload_controller", to: "assethutch/direct_upload_controller.js"\n)
      end

      def show_next_steps
        say ""
        say "AssetHutch installed.", :green
        say "  1. Set ASSETHUTCH_API_KEY (Dashboard → API keys) and, if not production, ASSETHUTCH_URL."
        say "  2. Add a column and macro:  bin/rails g assethutch:attachment User avatar  then  has_assethutch_file :avatar, policy: \"avatars\""
        say "  3. For browser uploads, set Assethutch.config.authorize_direct_upload in the initializer and register the"
        say "     Stimulus controller:  application.register(\"assethutch-direct-upload\", DirectUploadController)"
      end
    end
  end
end
