# frozen_string_literal: true

Rails.application.routes.draw do
  mount FileHutch::Engine => "/file_hutch"
end
