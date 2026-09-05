# frozen_string_literal: true

AssetHutch.configure do |config|
  # Project-scoped API key from the AssetHutch dashboard. Keep it out of the repo.
  config.api_key = ENV["ASSET_HUTCH_API_KEY"]

  # Leave the default for AssetHutch cloud; point at your own instance otherwise.
  config.url = ENV.fetch("ASSET_HUTCH_URL", AssetHutch::Configuration::DEFAULT_URL)

  # Browser-direct uploads (POST /asset_hutch/uploads) are off until you decide who may
  # upload, and against which policies. `controller` is the request's controller.
  # config.authorize_direct_upload = ->(controller, policy) do
  #   controller.current_user.present? && %w[avatars documents].include?(policy)
  # end

  # The direct-upload controller inherits from this so your auth helpers are available.
  # config.direct_upload_parent_controller = "ApplicationController"
end
