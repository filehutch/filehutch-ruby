# frozen_string_literal: true

class Document < ActiveRecord::Base
  has_hutch :report, policy: "documents"
  has_hutch :avatar, policy: "avatars", dependent: false, verify: false
end
