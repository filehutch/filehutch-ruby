# frozen_string_literal: true

require_relative "lib/file_hutch/version"

Gem::Specification.new do |spec|
  spec.name = "file_hutch"
  spec.version = FileHutch::VERSION
  spec.authors = [ "Andy Leverenz" ]
  spec.email = [ "andy@justalever.com" ]

  spec.summary = "Ruby and Rails client for FileHutch: uploads, private files, and delivery without file plumbing."
  spec.description = "Talk to the FileHutch file control plane from Ruby. Server-side and browser-direct uploads, " \
                     "signed URLs, and a has_hutch macro for Active Record that stores only opaque file ids."
  spec.homepage = "https://github.com/filehutch/filehutch-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["{app,config,exe,lib}/**/*", "LICENSE.txt", "README.md", "CHANGELOG.md"]
  spec.bindir = "exe"
  spec.executables = [ "file_hutch" ]
  spec.require_paths = [ "lib" ]

  # Stdlib only at runtime. Rails integration activates when Rails is present.
end
