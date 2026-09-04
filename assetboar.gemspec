# frozen_string_literal: true

require_relative "lib/assetboar/version"

Gem::Specification.new do |spec|
  spec.name = "assetboar"
  spec.version = Assetboar::VERSION
  spec.authors = [ "Andy Leverenz" ]
  spec.email = [ "andy@justalever.com" ]

  spec.summary = "Ruby and Rails client for AssetBoar: uploads, private files, and delivery without file plumbing."
  spec.description = "Talk to the AssetBoar file control plane from Ruby. Server-side and browser-direct uploads, " \
                     "signed URLs, and a has_assetboar_file macro for Active Record that stores only opaque file ids."
  spec.homepage = "https://github.com/assetboar/assetboar-ruby"
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
