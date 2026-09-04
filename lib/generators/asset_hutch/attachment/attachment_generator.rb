# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module AssetHutch
  module Generators
    # bin/rails generate asset_hutch:attachment User avatar
    # Adds users.avatar_file_id (string). Pair with `has_asset_hutch_file :avatar, policy: "…"`.
    class AttachmentGenerator < ::Rails::Generators::NamedBase
      include ::ActiveRecord::Generators::Migration

      source_root ::File.expand_path("templates", __dir__)
      argument :attachment, type: :string, banner: "attachment_name"

      def create_migration_file
        migration_template "migration.rb.tt", "db/migrate/add_#{column_name}_to_#{table_name}.rb"
      end

      def show_macro
        say %(Add to #{class_name}:  has_asset_hutch_file :#{attachment}, policy: "#{attachment.pluralize}"), :green
      end

      private

      def column_name = "#{attachment.underscore}_file_id"
      def migration_class_name = "Add#{column_name.camelize}To#{table_name.camelize}"
    end
  end
end
