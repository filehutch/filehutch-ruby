# frozen_string_literal: true

AssetHutch::Engine.routes.draw do
  resources :uploads, only: :create, controller: "direct_uploads" do
    post :complete, on: :member
  end
end
