# frozen_string_literal: true

require "active_support/concern"

module Assethutch
  # `has_assethutch_file` for Active Record. The model stores one string column,
  # `<name>_file_id`, holding an AssetHutch file id. Nothing about storage leaks in.
  #
  #   class User < ApplicationRecord
  #     has_assethutch_file :avatar, policy: "avatars"
  #   end
  #
  #   user.avatar = params[:avatar]            # uploaded IO: uploaded to storage on save
  #   user.avatar = "file_…"                   # id from a browser direct upload: verified on save
  #   user.avatar                              # => Assethutch::File or nil
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
      def has_assethutch_file(name, policy:, column: "#{name}_file_id", dependent: :delete, verify: true)
        include Attachable unless include?(Attachable)
        name = name.to_sym
        column = column.to_s
        assethutch_files[name] = { policy: policy.to_s, column: column, dependent: dependent, verify: verify }

        validate { assethutch_validate(name) }
        before_save { assethutch_upload_staged(name) }
        after_save { assethutch_delete_replaced(name) }
        after_destroy { assethutch_delete_on_destroy(name) } if dependent == :delete

        define_method(name) { assethutch_file(name) }
        define_method(:"#{name}=") { |value| assethutch_assign(name, value) }
        define_method(:"#{name}?") { self[column].present? }
        define_method(:"#{name}_url") { assethutch_file(name)&.url }
        define_method(:"#{name}_signed_url") { |expires_in: nil, disposition: nil| assethutch_file(name)&.signed_url(expires_in: expires_in, disposition: disposition) }
        define_method(:"purge_#{name}") { assethutch_purge(name) }
      end

      def assethutch_files
        @assethutch_files ||= superclass.respond_to?(:assethutch_files) ? superclass.assethutch_files.dup : {}
      end
    end

    def reload(*)
      @assethutch_cache = nil
      super
    end

    private

    def assethutch_option(name, key) = self.class.assethutch_files.fetch(name).fetch(key)
    def assethutch_cache = @assethutch_cache ||= {}
    def assethutch_staged = @assethutch_staged ||= {}
    def assethutch_replaced = @assethutch_replaced ||= {}

    def assethutch_file(name)
      id = self[assethutch_option(name, :column)]
      return nil if id.blank?
      cached = assethutch_cache[name]
      return cached if cached && cached.id == id
      assethutch_cache[name] = Assethutch.client.file(id)
    rescue Assethutch::NotFoundError
      nil
    end

    def assethutch_assign(name, value)
      column = assethutch_option(name, :column)
      previous = self[column]
      assethutch_staged.delete(name)
      assethutch_cache.delete(name)

      case value
      when nil, ""
        self[column] = nil
      when Assethutch::File
        assethutch_cache[name] = value
        self[column] = value.id
      when String
        raise ArgumentError, "#{value.inspect} is not an AssetHutch file id" unless Assethutch::File.id?(value)
        self[column] = value
      else
        raise ArgumentError, "cannot attach #{value.class} to #{name}" unless value.respond_to?(:read) || value.respond_to?(:tempfile) || value.is_a?(Pathname)
        assethutch_staged[name] = value
        self[column] = nil
      end

      assethutch_remember_replaced(name, previous) if previous.present? && previous != self[column]
      value
    end

    def assethutch_remember_replaced(name, previous_id)
      assethutch_replaced[name] = previous_id if assethutch_option(name, :dependent) == :delete
    end

    def assethutch_validate(name)
      column = assethutch_option(name, :column)
      staged = assethutch_staged[name]
      if staged
        policy = assethutch_policy(name)
        if policy
          type = staged.respond_to?(:content_type) ? staged.content_type : nil
          size = staged.respond_to?(:size) ? staged.size : nil
          errors.add(name, :assethutch_content_type, message: "type #{type} is not allowed") if type && !policy.allows_content_type?(type)
          errors.add(name, :assethutch_too_large, message: "is larger than #{policy.maximum_size} bytes") if size && !policy.allows_byte_size?(size)
        end
        return
      end

      id = self[column]
      return unless assethutch_option(name, :verify) && id.present? && attribute_changed?(column) && assethutch_cache[name].nil?

      file = Assethutch.client.file(id)
      if !file.ready?
        errors.add(name, :assethutch_not_ready, message: "upload is #{file.status}")
      elsif file.policy != assethutch_option(name, :policy)
        errors.add(name, :assethutch_wrong_policy, message: "was uploaded under the #{file.policy} policy")
      else
        assethutch_cache[name] = file
      end
    rescue Assethutch::NotFoundError
      errors.add(name, :assethutch_not_found, message: "does not exist")
    end

    # Policies are fetched once per process; a miss (or an outage) skips local checks. The server still enforces them.
    def assethutch_policy(name)
      Attachable.policy(assethutch_option(name, :policy))
    end

    def assethutch_upload_staged(name)
      source = assethutch_staged.delete(name) or return
      file = Assethutch.client.upload(source, policy: assethutch_option(name, :policy))
      assethutch_cache[name] = file
      self[assethutch_option(name, :column)] = file.id
    end

    def assethutch_delete_replaced(name)
      id = assethutch_replaced.delete(name) or return
      return if id == self[assethutch_option(name, :column)]
      Attachable.delete_quietly(id)
    end

    def assethutch_delete_on_destroy(name)
      id = self[assethutch_option(name, :column)]
      Attachable.delete_quietly(id) if id.present?
    end

    def assethutch_purge(name)
      column = assethutch_option(name, :column)
      id = self[column]
      Attachable.delete_quietly(id) if id.present?
      assethutch_cache.delete(name)
      update_column(column, nil) if persisted?
      self[column] = nil
      true
    end

    class << self
      def delete_quietly(id)
        Assethutch.client.delete_file(id)
      rescue Assethutch::NotFoundError, Assethutch::InvalidStateError
        true
      end

      def policy(name)
        policies[name] ||= Assethutch.client.project.upload_policy(name)
      rescue Assethutch::Error => e
        Assethutch.config.logger&.warn { "[assethutch] could not load upload policies: #{e.message}" }
        nil
      end

      def policies = @policies ||= {}
      def reset_policies! = @policies = {}
    end
  end
end
