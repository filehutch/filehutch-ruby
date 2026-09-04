# frozen_string_literal: true

Rails.application.routes.draw do
  mount AssetHutch::Engine => "/assethutch"
end
