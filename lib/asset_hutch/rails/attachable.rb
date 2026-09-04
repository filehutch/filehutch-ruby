# frozen_string_literal: true

require "active_support/concern"

module AssetHutch
  # `has_asset_hutch_file` for Active Record. The model stores one string column,
  # `<name>_file_id`, holding an AssetHutch file id. Nothing about storage leaks in.
  #
  #   class User < ApplicationRecord
  #     has_asset_hutch_file :avatar, policy: "avatars"
  #   end
  #
  #   user.avatar = params[:avatar]            # uploaded IO: uploaded to storage on save
  #   user.avatar = "file_…"                   # id from a browser direct upload: verified on save
  #   user.avatar                              # => AssetHutch::File or nil
  #   user.avatar_url                          # public URL (public policies)
  #   user.avatar_signed_url(expires_in: 600)  # works for private files
  #   user.avatar_transform_url("thumb")       # a named transform from the dashboard
  #   user.purge_avatar                        # deletes remotely, clears the column
  #
  # Options: column: (default "<name>_file_id"), dependent: :delete (default; delete the file when the
  # record is destroyed or the file is replaced) or false, verify: true (default; a raw id assigned
  # from a form is fetched on validation and must be a ready file uploaded under this policy).
  module Attachable
    extend ActiveSupport::Concern

    class_methods do
      def has_asset_hutch_file(name, policy:, column: "#{name}_file_id", dependent: :delete, verify: true)
        include Attachable unless include?(Attachable)
        name = name.to_sym
        column = column.to_s
        asset_hutch_files[name] = { policy: policy.to_s, column: column, dependent: dependent, verify: verify }

        validate { asset_hutch_validate(name) }
        before_save { asset_hutch_upload_staged(name) }
        after_save { asset_hutch_delete_replaced(name) }
        after_destroy { asset_hutch_delete_on_destroy(name) } if dependent == :delete

        define_method(name) { asset_hutch_file(name) }
        define_method(:"#{name}=") { |value| asset_hutch_assign(name, value) }
        define_method(:"#{name}?") { self[column].present? }
        define_method(:"#{name}_url") { asset_hutch_file(name)&.url }
        define_method(:"#{name}_signed_url") { |expires_in: nil, disposition: nil| asset_hutch_file(name)&.signed_url(expires_in: expires_in, disposition: disposition) }
        define_method(:"#{name}_transform_url") { |transform, expires_in: nil| asset_hutch_file(name)&.transform_url(transform, expires_in: expires_in) }
        define_method(:"purge_#{name}") { asset_hutch_purge(name) }
      end

      def asset_hutch_files
        @asset_hutch_files ||= superclass.respond_to?(:asset_hutch_files) ? superclass.asset_hutch_files.dup : {}
      end
    end

    def reload(*)
      @asset_hutch_cache = nil
      super
    end

    private

    def asset_hutch_option(name, key) = self.class.asset_hutch_files.fetch(name).fetch(key)
    def asset_hutch_cache = @asset_hutch_cache ||= {}
    def asset_hutch_staged = @asset_hutch_staged ||= {}
    def asset_hutch_replaced = @asset_hutch_replaced ||= {}

    def asset_hutch_file(name)
      id = self[asset_hutch_option(name, :column)]
      return nil if id.blank?
      cached = asset_hutch_cache[name]
      return cached if cached && cached.id == id
      asset_hutch_cache[name] = AssetHutch.client.file(id)
    rescue AssetHutch::NotFoundError
      nil
    end

    def asset_hutch_assign(name, value)
      column = asset_hutch_option(name, :column)
      previous = self[column]
      asset_hutch_staged.delete(name)
      asset_hutch_cache.delete(name)

      case value
      when nil, ""
        self[column] = nil
      when AssetHutch::File
        asset_hutch_cache[name] = value
        self[column] = value.id
      when String
        raise ArgumentError, "#{value.inspect} is not an AssetHutch file id" unless AssetHutch::File.id?(value)
        self[column] = value
      else
        raise ArgumentError, "cannot attach #{value.class} to #{name}" unless value.respond_to?(:read) || value.respond_to?(:tempfile) || value.is_a?(Pathname)
        asset_hutch_staged[name] = value
        self[column] = nil
      end

      asset_hutch_remember_replaced(name, previous) if previous.present? && previous != self[column]
      value
    end

    def asset_hutch_remember_replaced(name, previous_id)
      asset_hutch_replaced[name] = previous_id if asset_hutch_option(name, :dependent) == :delete
    end

    def asset_hutch_validate(name)
      column = asset_hutch_option(name, :column)
      staged = asset_hutch_staged[name]
      if staged
        policy = asset_hutch_policy(name)
        if policy
          type = staged.respond_to?(:content_type) ? staged.content_type : nil
          size = staged.respond_to?(:size) ? staged.size : nil
          errors.add(name, :asset_hutch_content_type, message: "type #{type} is not allowed") if type && !policy.allows_content_type?(type)
          errors.add(name, :asset_hutch_too_large, message: "is larger than #{policy.maximum_size} bytes") if size && !policy.allows_byte_size?(size)
        end
        return
      end

      id = self[column]
      return unless asset_hutch_option(name, :verify) && id.present? && attribute_changed?(column) && asset_hutch_cache[name].nil?

      file = AssetHutch.client.file(id)
      if !file.ready?
        errors.add(name, :asset_hutch_not_ready, message: "upload is #{file.status}")
      elsif file.policy != asset_hutch_option(name, :policy)
        errors.add(name, :asset_hutch_wrong_policy, message: "was uploaded under the #{file.policy} policy")
      else
        asset_hutch_cache[name] = file
      end
    rescue AssetHutch::NotFoundError
      errors.add(name, :asset_hutch_not_found, message: "does not exist")
    end

    # Policies are fetched once per process; a miss (or an outage) skips local checks. The server still enforces them.
    def asset_hutch_policy(name)
      Attachable.policy(asset_hutch_option(name, :policy))
    end

    def asset_hutch_upload_staged(name)
      source = asset_hutch_staged.delete(name) or return
      file = AssetHutch.client.upload(source, policy: asset_hutch_option(name, :policy))
      asset_hutch_cache[name] = file
      self[asset_hutch_option(name, :column)] = file.id
    end

    def asset_hutch_delete_replaced(name)
      id = asset_hutch_replaced.delete(name) or return
      return if id == self[asset_hutch_option(name, :column)]
      Attachable.delete_quietly(id)
    end

    def asset_hutch_delete_on_destroy(name)
      id = self[asset_hutch_option(name, :column)]
      Attachable.delete_quietly(id) if id.present?
    end

    def asset_hutch_purge(name)
      column = asset_hutch_option(name, :column)
      id = self[column]
      Attachable.delete_quietly(id) if id.present?
      asset_hutch_cache.delete(name)
      update_column(column, nil) if persisted?
      self[column] = nil
      true
    end

    class << self
      def delete_quietly(id)
        AssetHutch.client.delete_file(id)
      rescue AssetHutch::NotFoundError, AssetHutch::InvalidStateError
        true
      end

      def policy(name)
        policies[name] ||= AssetHutch.client.project.upload_policy(name)
      rescue AssetHutch::Error => e
        AssetHutch.config.logger&.warn { "[asset_hutch] could not load upload policies: #{e.message}" }
        nil
      end

      def policies = @policies ||= {}
      def reset_policies! = @policies = {}
    end
  end
end
