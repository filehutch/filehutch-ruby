# frozen_string_literal: true

require_relative "lib/asset_hutch/version"

Gem::Specification.new do |spec|
  spec.name = "asset_hutch"
  spec.version = AssetHutch::VERSION
  spec.authors = [ "Andy Leverenz" ]
  spec.email = [ "andy@justalever.com" ]

  spec.summary = "Ruby and Rails client for AssetHutch: uploads, private files, and delivery without file plumbing."
  spec.description = "Talk to the AssetHutch file control plane from Ruby. Server-side and browser-direct uploads, " \
                     "signed URLs, and a has_asset_hutch_file macro for Active Record that stores only opaque file ids."
  spec.homepage = "https://github.com/assethutch/assethutch-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["{app,config,lib}/**/*", "LICENSE.txt", "README.md", "CHANGELOG.md"]
  spec.require_paths = [ "lib" ]

  # Stdlib only at runtime. Rails integration activates when Rails is present.
end
