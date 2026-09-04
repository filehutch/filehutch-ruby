# frozen_string_literal: true

class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception

  # The dummy app's idea of auth: a header, so tests can flip it.
  def current_user
    request.headers["X-User"].presence
  end
end
