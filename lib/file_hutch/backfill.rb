# frozen_string_literal: true

module FileHutch
  # Moves one Active Storage attachment on a model onto its has_hutch column:
  #
  #   FileHutch::Backfill.new(model: User, from: :photo, to: :avatar).call
  #
  # Two ways, per run:
  #
  # * Stream (the default). Each blob's bytes are read through Active Storage
  #   and uploaded to FileHutch under the attachment's policy. Works whatever
  #   bucket Active Storage uses, and costs a download and an upload per file.
  #
  # * Adopt (adopt_from: "conn_…"). When the bucket Active Storage writes to is
  #   connected to FileHutch, each blob is registered where it already is, by
  #   its key. Nothing is copied or downloaded.
  #
  # Restartable. Only records whose column is still blank are touched, and the
  # column is written as soon as each file exists, so a run that stops half way
  # carries on from where it was. Adopting is idempotent on the server too.
  #
  # The Active Storage attachment is left alone: keep reading from it until the
  # new column is filled everywhere, then remove it.
  class Backfill
    Result = Struct.new(:done, :skipped, :failed, keyword_init: true)

    def initialize(model:, from:, to: from, adopt_from: nil, client: FileHutch.client, logger: FileHutch.config.logger)
      @model, @from, @to, @adopt_from, @client, @logger = model, from.to_sym, to.to_sym, adopt_from.presence, client, logger
      @options = model.file_hutch_files.fetch(@to) do
        raise ArgumentError, "#{model.name} has no has_hutch :#{@to}"
      end
    end

    def call
      result = Result.new(done: 0, skipped: 0, failed: 0)

      @model.where(column => [ nil, "" ]).find_each do |record|
        attachment = record.public_send(@from)
        unless attachment.respond_to?(:attached?) && attachment.attached?
          result.skipped += 1
          next
        end

        file = @adopt_from ? adopt(attachment.blob) : stream(attachment.blob)
        # update_column: the file exists already, so has_hutch's check on save
        # would only ask the server again, and callbacks have no business here.
        record.update_column(column, file.id)
        result.done += 1
      rescue FileHutch::Error => e
        result.failed += 1
        @logger&.warn("[file_hutch] backfill #{@model.name}##{record.id} #{@from}: #{e.message}")
      end

      result
    end

    private

    def column = @options.fetch(:column)
    def policy = @options.fetch(:policy)

    def adopt(blob)
      @client.adopt(storage_connection: @adopt_from, key: blob.key, filename: blob.filename.to_s,
                    content_type: blob.content_type, policy: policy)
    end

    def stream(blob)
      blob.open do |io|
        @client.upload(io, policy: policy, filename: blob.filename.to_s, content_type: blob.content_type)
      end
    end
  end
end
