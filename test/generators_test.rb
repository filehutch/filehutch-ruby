# frozen_string_literal: true

require "test_helper"
require "rails/generators/test_case"
require "generators/assetboar/install/install_generator"
require "generators/assetboar/attachment/attachment_generator"

class InstallGeneratorTest < Rails::Generators::TestCase
  tests Assetboar::Generators::InstallGenerator
  destination File.expand_path("../tmp/generators", __dir__)
  setup do
    prepare_destination
    FileUtils.mkdir_p("#{destination_root}/config")
    File.write("#{destination_root}/config/routes.rb", "Rails.application.routes.draw do\nend\n")
    File.write("#{destination_root}/config/importmap.rb", "pin \"application\"\n")
  end

  test "creates the initializer, mounts the engine, and pins the controller" do
    run_generator
    assert_file "config/initializers/assetboar.rb", /Assetboar.configure/
    assert_file "config/routes.rb", /mount Assetboar::Engine => "\/assetboar"/
    assert_file "config/importmap.rb", /pin "assetboar\/direct_upload_controller"/
  end
end

class AttachmentGeneratorTest < Rails::Generators::TestCase
  tests Assetboar::Generators::AttachmentGenerator
  destination File.expand_path("../tmp/generators", __dir__)
  setup { prepare_destination }

  test "adds a string column for the file id" do
    run_generator %w[User avatar]
    assert_migration "db/migrate/add_avatar_file_id_to_users.rb" do |migration|
      assert_match(/class AddAvatarFileIdToUsers < ActiveRecord::Migration\[\d\.\d\]/, migration)
      assert_match(/add_column :users, :avatar_file_id, :string/, migration)
    end
  end
end
