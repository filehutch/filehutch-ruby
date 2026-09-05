# frozen_string_literal: true

FileHutch.configure do |config|
  # Project-scoped API key from the FileHutch dashboard. Keep it out of the repo.
  config.api_key = ENV["FILE_HUTCH_API_KEY"]

  # Leave the default for FileHutch cloud; point at your own instance otherwise.
  config.url = ENV.fetch("FILE_HUTCH_URL", FileHutch::Configuration::DEFAULT_URL)

  # Browser-direct uploads (POST /file_hutch/uploads) are off until you decide who may
  # upload, and against which policies. `controller` is the request's controller.
  # config.authorize_direct_upload = ->(controller, policy) do
  #   controller.current_user.present? && %w[avatars documents].include?(policy)
  # end

  # The direct-upload controller inherits from this so your auth helpers are available.
  # config.direct_upload_parent_controller = "ApplicationController"
end
