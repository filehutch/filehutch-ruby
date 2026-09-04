# frozen_string_literal: true

class Document < ActiveRecord::Base
  has_assetboar_file :report, policy: "documents"
  has_assetboar_file :avatar, policy: "avatars", dependent: false, verify: false
end
