# frozen_string_literal: true

require "active_support/concern"

module Assetboar
  # `has_assetboar_file` for Active Record. The model stores one string column,
  # `<name>_file_id`, holding an AssetBoar file id. Nothing about storage leaks in.
  #
  #   class User < ApplicationRecord
  #     has_assetboar_file :avatar, policy: "avatars"
  #   end
  #
  #   user.avatar = params[:avatar]            # uploaded IO: uploaded to storage on save
  #   user.avatar = "file_…"                   # id from a browser direct upload: verified on save
  #   user.avatar                              # => Assetboar::File or nil
  #   user.avatar_url                          # public URL (public policies)
  #   user.avatar_signed_url(expires_in: 600)  # works for private files
  #   user.purge_avatar                        # deletes remotely, clears the column
  #
  # Options: column: (default "<name>_file_id"), dependent: :delete (default; delete the file when the
  # record is destroyed or the file is replaced) or false, verify: true (default; a raw id assigned
  # from a form is fetched on validation and must be a ready file uploaded under this policy).
  module Attachable
    extend ActiveSupport::Concern

    class_methods do
      def has_assetboar_file(name, policy:, column: "#{name}_file_id", dependent: :delete, verify: true)
        include Attachable unless include?(Attachable)
        name = name.to_sym
        column = column.to_s
        assetboar_files[name] = { policy: policy.to_s, column: column, dependent: dependent, verify: verify }

        validate { assetboar_validate(name) }
        before_save { assetboar_upload_staged(name) }
        after_save { assetboar_delete_replaced(name) }
        after_destroy { assetboar_delete_on_destroy(name) } if dependent == :delete

        define_method(name) { assetboar_file(name) }
        define_method(:"#{name}=") { |value| assetboar_assign(name, value) }
        define_method(:"#{name}?") { self[column].present? }
        define_method(:"#{name}_url") { assetboar_file(name)&.url }
        define_method(:"#{name}_signed_url") { |expires_in: nil, disposition: nil| assetboar_file(name)&.signed_url(expires_in: expires_in, disposition: disposition) }
        define_method(:"purge_#{name}") { assetboar_purge(name) }
      end

      def assetboar_files
        @assetboar_files ||= superclass.respond_to?(:assetboar_files) ? superclass.assetboar_files.dup : {}
      end
    end

    def reload(*)
      @assetboar_cache = nil
      super
    end

    private

    def assetboar_option(name, key) = self.class.assetboar_files.fetch(name).fetch(key)
    def assetboar_cache = @assetboar_cache ||= {}
    def assetboar_staged = @assetboar_staged ||= {}
    def assetboar_replaced = @assetboar_replaced ||= {}

    def assetboar_file(name)
      id = self[assetboar_option(name, :column)]
      return nil if id.blank?
      cached = assetboar_cache[name]
      return cached if cached && cached.id == id
      assetboar_cache[name] = Assetboar.client.file(id)
    rescue Assetboar::NotFoundError
      nil
    end

    def assetboar_assign(name, value)
      column = assetboar_option(name, :column)
      previous = self[column]
      assetboar_staged.delete(name)
      assetboar_cache.delete(name)

      case value
      when nil, ""
        self[column] = nil
      when Assetboar::File
        assetboar_cache[name] = value
        self[column] = value.id
      when String
        raise ArgumentError, "#{value.inspect} is not an AssetBoar file id" unless Assetboar::File.id?(value)
        self[column] = value
      else
        raise ArgumentError, "cannot attach #{value.class} to #{name}" unless value.respond_to?(:read) || value.respond_to?(:tempfile) || value.is_a?(Pathname)
        assetboar_staged[name] = value
        self[column] = nil
      end

      assetboar_remember_replaced(name, previous) if previous.present? && previous != self[column]
      value
    end

    def assetboar_remember_replaced(name, previous_id)
      assetboar_replaced[name] = previous_id if assetboar_option(name, :dependent) == :delete
    end

    def assetboar_validate(name)
      column = assetboar_option(name, :column)
      staged = assetboar_staged[name]
      if staged
        policy = assetboar_policy(name)
        if policy
          type = staged.respond_to?(:content_type) ? staged.content_type : nil
          size = staged.respond_to?(:size) ? staged.size : nil
          errors.add(name, :assetboar_content_type, message: "type #{type} is not allowed") if type && !policy.allows_content_type?(type)
          errors.add(name, :assetboar_too_large, message: "is larger than #{policy.maximum_size} bytes") if size && !policy.allows_byte_size?(size)
        end
        return
      end

      id = self[column]
      return unless assetboar_option(name, :verify) && id.present? && attribute_changed?(column) && assetboar_cache[name].nil?

      file = Assetboar.client.file(id)
      if !file.ready?
        errors.add(name, :assetboar_not_ready, message: "upload is #{file.status}")
      elsif file.policy != assetboar_option(name, :policy)
        errors.add(name, :assetboar_wrong_policy, message: "was uploaded under the #{file.policy} policy")
      else
        assetboar_cache[name] = file
      end
    rescue Assetboar::NotFoundError
      errors.add(name, :assetboar_not_found, message: "does not exist")
    end

    # Policies are fetched once per process; a miss (or an outage) skips local checks. The server still enforces them.
    def assetboar_policy(name)
      Attachable.policy(assetboar_option(name, :policy))
    end

    def assetboar_upload_staged(name)
      source = assetboar_staged.delete(name) or return
      file = Assetboar.client.upload(source, policy: assetboar_option(name, :policy))
      assetboar_cache[name] = file
      self[assetboar_option(name, :column)] = file.id
    end

    def assetboar_delete_replaced(name)
      id = assetboar_replaced.delete(name) or return
      return if id == self[assetboar_option(name, :column)]
      Attachable.delete_quietly(id)
    end

    def assetboar_delete_on_destroy(name)
      id = self[assetboar_option(name, :column)]
      Attachable.delete_quietly(id) if id.present?
    end

    def assetboar_purge(name)
      column = assetboar_option(name, :column)
      id = self[column]
      Attachable.delete_quietly(id) if id.present?
      assetboar_cache.delete(name)
      update_column(column, nil) if persisted?
      self[column] = nil
      true
    end

    class << self
      def delete_quietly(id)
        Assetboar.client.delete_file(id)
      rescue Assetboar::NotFoundError, Assetboar::InvalidStateError
        true
      end

      def policy(name)
        policies[name] ||= Assetboar.client.project.upload_policy(name)
      rescue Assetboar::Error => e
        Assetboar.config.logger&.warn { "[assetboar] could not load upload policies: #{e.message}" }
        nil
      end

      def policies = @policies ||= {}
      def reset_policies! = @policies = {}
    end
  end
end
