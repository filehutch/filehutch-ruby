# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "rake"
gem "minitest"
gem "webmock"
gem "rails", "~> 8.1"
gem "sqlite3"
gem "rubocop-rails-omakase", require: false

# Rails 8.1.3.1's ActiveSupport::JSON.decode calls JSON.parse(json, options)
# with the options positional, which json 3 refuses — so every JSON request
# body in the dummy app fails to parse and the engine's tests 400. The gem's
# own code passes one argument and is unaffected, and the gemspec declares no
# runtime dependencies, so this constrains the test harness only. Drop it when
# Rails ships a release that speaks json 3.
gem "json", "< 3"
