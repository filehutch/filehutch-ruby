# frozen_string_literal: true

require "rails/generators"

module FileHutch
  module Generators
    # bin/rails generate file_hutch:install
    class InstallGenerator < ::Rails::Generators::Base
      source_root ::File.expand_path("templates", __dir__)

      def create_initializer
        template "initializer.rb", "config/initializers/file_hutch.rb"
      end

      def mount_engine
        route 'mount FileHutch::Engine => "/file_hutch"'
      end

      def pin_javascript
        return unless ::File.exist?(::File.join(destination_root, "config/importmap.rb"))
        append_to_file "config/importmap.rb", %(pin "file_hutch/direct_upload_controller", to: "file_hutch/direct_upload_controller.js"\n)
      end

      def show_next_steps
        say ""
        say "FileHutch installed.", :green
        say "  1. Set FILE_HUTCH_API_KEY (Dashboard → API keys) and, if not production, FILE_HUTCH_URL."
        say "  2. Add a column and macro:  bin/rails g file_hutch:attachment User avatar  then  has_file_hutch_file :avatar, policy: \"avatars\""
        say "  3. For browser uploads, set FileHutch.config.authorize_direct_upload in the initializer and register the"
        say "     Stimulus controller:  application.register(\"filehutch-direct-upload\", DirectUploadController)"
      end
    end
  end
end
