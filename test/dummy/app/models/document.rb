# frozen_string_literal: true

class Document < ActiveRecord::Base
  has_file_hutch_file :report, policy: "documents"
  has_file_hutch_file :avatar, policy: "avatars", dependent: false, verify: false
end
