# frozen_string_literal: true

Rails.application.routes.draw do
  mount Assethutch::Engine => "/assethutch"
end
