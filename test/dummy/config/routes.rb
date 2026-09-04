# frozen_string_literal: true

Rails.application.routes.draw do
  mount Assetboar::Engine => "/assetboar"
end
