# frozen_string_literal: true

module Assetboar
  # HTTP client for the AssetBoar v1 API. Stdlib only.
  #
  #   client = Assetboar::Client.new(api_key: "ab_…", url: "https://api.assetboar.com")
  #   client.upload("report.pdf", policy: "documents")        # 3-step direct upload, returns the ready file
  #   client.file("file_…").signed_url(expires_in: 600)
  class Client
    JSON_TYPE = "application/json"
    NET_ERRORS = [ Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH,
                   Errno::EPIPE, SocketError, OpenSSL::SSL::SSLError, Net::OpenTimeout, Net::ReadTimeout, EOFError, IOError ].freeze

    attr_reader :config

    # Accepts a Configuration or keyword overrides on top of the global one.
    def initialize(config = nil, **overrides)
      @config = (config || Assetboar.configuration).dup
      overrides.each { |k, v| @config.public_send(:"#{k}=", v) }
      @config.validate!
      @base = URI(@config.url.to_s.sub(%r{/+\z}, ""))
    end

    # -- Resources ---------------------------------------------------------

    def project
      Project.new(request(:get, "/api/v1/project").fetch("project"), client: self)
    end

    def file(id)
      File.new(request(:get, "/api/v1/files/#{path_id(id)}").fetch("file"), client: self)
    end

    def create_upload(policy:, filename:, content_type:, byte_size:, metadata: nil)
      body = { policy: policy, filename: filename, content_type: content_type, byte_size: byte_size }
      body[:metadata] = metadata if metadata && !metadata.empty?
      data = request(:post, "/api/v1/uploads", body)
      Upload.new(data.fetch("upload"), file: File.new(data.fetch("file"), client: self), client: self)
    end

    def complete_upload(id)
      File.new(request(:post, "/api/v1/uploads/#{path_id(id)}/complete").fetch("file"), client: self)
    end

    def signed_url(id, expires_in: nil, disposition: nil)
      body = { expires_in: expires_in, disposition: disposition }.compact
      data = request(:post, "/api/v1/files/#{path_id(id)}/signed_url", body)
      SignedUrl.new(url: data.fetch("url"), expires_at: Time.iso8601(data.fetch("expires_at")))
    end

    def delete_file(id)
      request(:delete, "/api/v1/files/#{path_id(id)}")
      true
    end

    # -- The whole upload flow, server side --------------------------------
    #
    # source: a path, Pathname, File, Tempfile, StringIO, ActionDispatch::Http::UploadedFile,
    #         or a String of bytes (pass filename: then).
    # Returns the ready Assetboar::File. Bytes go straight to storage.
    def upload(source, policy:, filename: nil, content_type: nil, metadata: nil)
      io, name, type, size = Source.open(source, filename: filename, content_type: content_type)
      upload = create_upload(policy: policy, filename: name, content_type: type, byte_size: size, metadata: metadata)
      put_to_storage(upload, io)
      complete_upload(upload.id)
    ensure
      io&.close if io && Source.owned?(io, source)
    end

    # PUT bytes to the storage URL in an upload authorization. Never hits an AssetBoar endpoint.
    def put_to_storage(upload, source)
      io, _name, _type, size = Source.open(source, filename: upload.file&.filename, content_type: upload.headers["Content-Type"])
      uri = URI(upload.url)
      req = Net::HTTP.const_get(upload.method.to_s.capitalize).new(uri)
      upload.headers.each { |k, v| req[k] = v }
      req["Content-Length"] = size.to_s
      req.body_stream = io
      response = http(uri) { |h| h.request(req) }
      unless response.is_a?(Net::HTTPSuccess)
        raise UploadError.new("Storage rejected the upload: HTTP #{response.code} #{response.body.to_s[0, 500]}".strip,
          code: "storage_rejected", status: response.code.to_i)
      end
      true
    ensure
      io&.close if io && Source.owned?(io, source)
    end

    # -- Transport ---------------------------------------------------------

    def request(method, path, body = nil)
      uri = URI.join("#{@base}/", path.sub(%r{\A/}, ""))
      req = Net::HTTP.const_get(method.to_s.capitalize).new(uri)
      req["Authorization"] = "Bearer #{config.api_key}"
      req["Accept"] = JSON_TYPE
      req["User-Agent"] = config.user_agent
      if body
        req["Content-Type"] = JSON_TYPE
        req.body = JSON.generate(body)
      end
      response = http(uri) { |h| h.request(req) }
      log(method, uri, response)
      parse(response)
    end

    private

    def http(uri)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: config.open_timeout,
                      read_timeout: config.read_timeout, write_timeout: config.write_timeout) { |h| yield h }
    rescue *NET_ERRORS => e
      raise ConnectionError.new("#{e.class}: #{e.message} (#{uri.host})", e)
    end

    def parse(response)
      status = response.code.to_i
      return nil if status == 204 || response.body.to_s.empty? && response.is_a?(Net::HTTPSuccess)

      data = begin
        JSON.parse(response.body)
      rescue JSON::ParserError
        nil
      end
      return data if response.is_a?(Net::HTTPSuccess)

      raise ApiError.build(status, data)
    end

    def path_id(id)
      value = id.respond_to?(:id) ? id.id : id.to_s
      raise ArgumentError, "expected an AssetBoar id, got #{id.inspect}" if value.to_s.empty? || value.to_s.include?("/")
      URI.encode_www_form_component(value)
    end

    def log(method, uri, response)
      config.logger&.debug { "[assetboar] #{method.to_s.upcase} #{uri.path} -> #{response.code}" }
    end

    # Normalizes the many things Ruby calls "a file" into [io, filename, content_type, byte_size].
    module Source
      TYPES = {
        ".pdf" => "application/pdf", ".png" => "image/png", ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg",
        ".gif" => "image/gif", ".webp" => "image/webp", ".avif" => "image/avif", ".svg" => "image/svg+xml",
        ".heic" => "image/heic", ".txt" => "text/plain", ".csv" => "text/csv", ".json" => "application/json",
        ".zip" => "application/zip", ".mp4" => "video/mp4", ".mp3" => "audio/mpeg", ".webm" => "video/webm",
        ".doc" => "application/msword", ".xls" => "application/vnd.ms-excel",
        ".docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        ".xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        ".pptx" => "application/vnd.openxmlformats-officedocument.presentationml.presentation"
      }.freeze
      FALLBACK = "application/octet-stream"

      module_function

      def open(source, filename: nil, content_type: nil)
        io = to_io(source, filename)
        name = filename || guess_filename(source, io)
        raise ArgumentError, "filename is required for #{source.class} sources" if name.nil? || name.to_s.empty?
        type = content_type || guess_content_type(source, name)
        io.rewind if io.respond_to?(:rewind)
        size = io.respond_to?(:size) ? io.size : io.stat.size
        [ io, ::File.basename(name.to_s), type, size ]
      end

      # We close IOs we opened ourselves (paths), never the caller's.
      def owned?(io, source) = path_like?(source) && io.is_a?(::File)

      def path_like?(source) = source.is_a?(Pathname) || (source.is_a?(String) && source.encoding != Encoding::BINARY && ::File.file?(source))

      def to_io(source, filename)
        return ::File.open(source.to_s, "rb") if path_like?(source)
        return source.tempfile if source.respond_to?(:tempfile) && source.tempfile
        return source if source.respond_to?(:read)
        return StringIO.new(source.b) if source.is_a?(String) && filename
        raise ArgumentError, "cannot upload #{source.class}; pass a path, IO, or bytes with filename:"
      end

      def guess_filename(source, io)
        return source.original_filename if source.respond_to?(:original_filename)
        return ::File.basename(source.to_s) if path_like?(source)
        return ::File.basename(io.path) if io.respond_to?(:path) && io.path
        nil
      end

      def guess_content_type(source, name)
        return source.content_type if source.respond_to?(:content_type) && !source.content_type.to_s.empty?
        return Marcel::MimeType.for(name: name.to_s) if defined?(Marcel::MimeType)
        TYPES.fetch(::File.extname(name.to_s).downcase, FALLBACK)
      end
    end
  end
end
