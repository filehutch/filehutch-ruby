# frozen_string_literal: true

module Assethutch
  class Project < Resource
    attribute :name, :team_id, :storage_ready
    time_attribute :created_at

    def storage_ready? = storage_ready == true
    def storage_connection = self["active_storage_connection"]
    def storage_mode = storage_connection && storage_connection["mode"]
    def storage_provider = storage_connection && storage_connection["provider"]

    def upload_policies
      (self["upload_policies"] || []).map { |p| UploadPolicy.new(p, client: client) }
    end

    def upload_policy(name) = upload_policies.find { |p| p.name == name.to_s || p.id == name.to_s }
  end

  class UploadPolicy < Resource
    attribute :name, :allowed_content_types, :maximum_size, :visibility
    time_attribute :created_at

    def public? = visibility == "public"
    def private? = visibility == "private"
    def allowed_content_types = self["allowed_content_types"] || []

    def allows_content_type?(content_type)
      return true if allowed_content_types.empty?
      ct = content_type.to_s.downcase
      allowed_content_types.any? { |p| p == ct || (p.end_with?("/*") && ct.start_with?(p.delete_suffix("*"))) }
    end

    def allows_byte_size?(size) = size.to_i.positive? && size.to_i <= maximum_size.to_i
  end
end
