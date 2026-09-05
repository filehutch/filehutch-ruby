# frozen_string_literal: true

require "active_support/concern"

module FileHutch
  # `has_file_hutch_file` for Active Record. The model stores one string column,
  # `<name>_file_id`, holding an FileHutch file id. Nothing about storage leaks in.
  #
  #   class User < ApplicationRecord
  #     has_file_hutch_file :avatar, policy: "avatars"
  #   end
  #
  #   user.avatar = params[:avatar]            # uploaded IO: uploaded to storage on save
  #   user.avatar = "file_…"                   # id from a browser direct upload: verified on save
  #   user.avatar                              # => FileHutch::File or nil
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
      def has_file_hutch_file(name, policy:, column: "#{name}_file_id", dependent: :delete, verify: true)
        include Attachable unless include?(Attachable)
        name = name.to_sym
        column = column.to_s
        file_hutch_files[name] = { policy: policy.to_s, column: column, dependent: dependent, verify: verify }

        validate { file_hutch_validate(name) }
        before_save { file_hutch_upload_staged(name) }
        after_save { file_hutch_delete_replaced(name) }
        after_destroy { file_hutch_delete_on_destroy(name) } if dependent == :delete

        define_method(name) { file_hutch_file(name) }
        define_method(:"#{name}=") { |value| file_hutch_assign(name, value) }
        define_method(:"#{name}?") { self[column].present? }
        define_method(:"#{name}_url") { file_hutch_file(name)&.url }
        define_method(:"#{name}_signed_url") { |expires_in: nil, disposition: nil| file_hutch_file(name)&.signed_url(expires_in: expires_in, disposition: disposition) }
        define_method(:"#{name}_transform_url") { |transform, expires_in: nil| file_hutch_file(name)&.transform_url(transform, expires_in: expires_in) }
        define_method(:"purge_#{name}") { file_hutch_purge(name) }
      end

      def file_hutch_files
        @file_hutch_files ||= superclass.respond_to?(:file_hutch_files) ? superclass.file_hutch_files.dup : {}
      end
    end

    def reload(*)
      @file_hutch_cache = nil
      super
    end

    private

    def file_hutch_option(name, key) = self.class.file_hutch_files.fetch(name).fetch(key)
    def file_hutch_cache = @file_hutch_cache ||= {}
    def file_hutch_staged = @file_hutch_staged ||= {}
    def file_hutch_replaced = @file_hutch_replaced ||= {}

    def file_hutch_file(name)
      id = self[file_hutch_option(name, :column)]
      return nil if id.blank?
      cached = file_hutch_cache[name]
      return cached if cached && cached.id == id
      file_hutch_cache[name] = FileHutch.client.file(id)
    rescue FileHutch::NotFoundError
      nil
    end

    def file_hutch_assign(name, value)
      column = file_hutch_option(name, :column)
      previous = self[column]
      file_hutch_staged.delete(name)
      file_hutch_cache.delete(name)

      case value
      when nil, ""
        self[column] = nil
      when FileHutch::File
        file_hutch_cache[name] = value
        self[column] = value.id
      when String
        raise ArgumentError, "#{value.inspect} is not an FileHutch file id" unless FileHutch::File.id?(value)
        self[column] = value
      else
        raise ArgumentError, "cannot attach #{value.class} to #{name}" unless value.respond_to?(:read) || value.respond_to?(:tempfile) || value.is_a?(Pathname)
        file_hutch_staged[name] = value
        self[column] = nil
      end

      file_hutch_remember_replaced(name, previous) if previous.present? && previous != self[column]
      value
    end

    def file_hutch_remember_replaced(name, previous_id)
      file_hutch_replaced[name] = previous_id if file_hutch_option(name, :dependent) == :delete
    end

    def file_hutch_validate(name)
      column = file_hutch_option(name, :column)
      staged = file_hutch_staged[name]
      if staged
        policy = file_hutch_policy(name)
        if policy
          type = staged.respond_to?(:content_type) ? staged.content_type : nil
          size = staged.respond_to?(:size) ? staged.size : nil
          errors.add(name, :file_hutch_content_type, message: "type #{type} is not allowed") if type && !policy.allows_content_type?(type)
          errors.add(name, :file_hutch_too_large, message: "is larger than #{policy.maximum_size} bytes") if size && !policy.allows_byte_size?(size)
        end
        return
      end

      id = self[column]
      return unless file_hutch_option(name, :verify) && id.present? && attribute_changed?(column) && file_hutch_cache[name].nil?

      file = FileHutch.client.file(id)
      if !file.ready?
        errors.add(name, :file_hutch_not_ready, message: "upload is #{file.status}")
      elsif file.policy != file_hutch_option(name, :policy)
        errors.add(name, :file_hutch_wrong_policy, message: "was uploaded under the #{file.policy} policy")
      else
        file_hutch_cache[name] = file
      end
    rescue FileHutch::NotFoundError
      errors.add(name, :file_hutch_not_found, message: "does not exist")
    end

    # Policies are fetched once per process; a miss (or an outage) skips local checks. The server still enforces them.
    def file_hutch_policy(name)
      Attachable.policy(file_hutch_option(name, :policy))
    end

    def file_hutch_upload_staged(name)
      source = file_hutch_staged.delete(name) or return
      file = FileHutch.client.upload(source, policy: file_hutch_option(name, :policy))
      file_hutch_cache[name] = file
      self[file_hutch_option(name, :column)] = file.id
    end

    def file_hutch_delete_replaced(name)
      id = file_hutch_replaced.delete(name) or return
      return if id == self[file_hutch_option(name, :column)]
      Attachable.delete_quietly(id)
    end

    def file_hutch_delete_on_destroy(name)
      id = self[file_hutch_option(name, :column)]
      Attachable.delete_quietly(id) if id.present?
    end

    def file_hutch_purge(name)
      column = file_hutch_option(name, :column)
      id = self[column]
      Attachable.delete_quietly(id) if id.present?
      file_hutch_cache.delete(name)
      update_column(column, nil) if persisted?
      self[column] = nil
      true
    end

    class << self
      def delete_quietly(id)
        FileHutch.client.delete_file(id)
      rescue FileHutch::NotFoundError, FileHutch::InvalidStateError
        true
      end

      def policy(name)
        policies[name] ||= FileHutch.client.project.upload_policy(name)
      rescue FileHutch::Error => e
        FileHutch.config.logger&.warn { "[file_hutch] could not load upload policies: #{e.message}" }
        nil
      end

      def policies = @policies ||= {}
      def reset_policies! = @policies = {}
    end
  end
end
