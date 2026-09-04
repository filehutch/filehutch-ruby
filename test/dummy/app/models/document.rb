# frozen_string_literal: true

class Document < ActiveRecord::Base
  has_assethutch_file :report, policy: "documents"
  has_assethutch_file :avatar, policy: "avatars", dependent: false, verify: false
end
