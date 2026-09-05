# frozen_string_literal: true

require "yaml"
require "optparse"

module FileHutch
  # `file_hutch` on the command line. Plan/apply a project's config file,
  # export it, inspect the project, upload a file, dump the manifest.
  # Reads FILE_HUTCH_API_KEY and FILE_HUTCH_URL like the library does.
  class CLI
    DEFAULT_FILE = "file_hutch.yml"
    MARK = { "create" => "+", "update" => "~", "delete" => "-", "noop" => "=" }.freeze

    USAGE = <<~TEXT
      Usage: file_hutch <command> [options]

        plan    [FILE] [--prune]          show what apply would change (read-only keys allowed)
        apply   [FILE] [--prune] [--yes]  make the project match FILE
        export                            print the project as a config file
        inspect                           project, environment, storage, plan and usage
        upload  PATH --policy NAME        direct upload, prints the file id
        manifest                          every ready file with its object key, as JSON lines
        version

      FILE defaults to #{DEFAULT_FILE}. Nothing is deleted without --prune; with --prune,
      apply asks before deleting unless --yes is given.
      Environment: FILE_HUTCH_API_KEY (required), FILE_HUTCH_URL.
    TEXT

    def initialize(argv, out: $stdout, err: $stderr, input: $stdin, client: nil)
      @argv, @out, @err, @input, @client = argv.dup, out, err, input, client
    end

    # Returns the exit status.
    def run
      command = @argv.shift
      case command
      when "plan" then plan
      when "apply" then apply
      when "export" then export
      when "inspect" then inspect_project
      when "upload" then upload
      when "manifest" then manifest
      when "version", "--version", "-v" then print_and_succeed("file_hutch #{VERSION}")
      when nil, "help", "--help", "-h" then print_and_succeed(USAGE)
      else
        @err.puts("Unknown command #{command.inspect}\n\n#{USAGE}")
        2
      end
    rescue ConfigurationError => e
      @err.puts(e.message)
      2
    rescue ApiError => e
      @err.puts("FileHutch said no (#{e.code}): #{e.message}")
      1
    rescue ConnectionError => e
      @err.puts("Could not reach FileHutch: #{e.message}")
      1
    end

    private

    def client
      @client ||= Client.new
    end

    def print_and_succeed(text)
      @out.puts(text)
      0
    end

    # -- plan / apply -------------------------------------------------------

    def plan
      options = parse_options
      config = read_config(options[:file]) or return 2
      plan = client.plan_config(config, prune: options[:prune])
      print_changes(plan["changes"])
      summary = plan["summary"]
      @out.puts "Plan: #{summary['create']} to create, #{summary['update']} to update, #{summary['delete']} to delete."
      0
    end

    def apply
      options = parse_options
      config = read_config(options[:file]) or return 2

      if options[:prune] && !options[:yes]
        plan = client.plan_config(config, prune: true)
        deletes = plan["changes"].select { |c| c["action"] == "delete" }
        if deletes.any?
          print_changes(deletes)
          @out.print "Delete #{deletes.size} #{deletes.size == 1 ? 'resource' : 'resources'}? [y/N] "
          @out.flush
          unless @input.gets.to_s.strip.downcase.start_with?("y")
            @out.puts "Nothing applied."
            return 1
          end
        end
      end

      result = client.apply_config(config, prune: options[:prune])
      result["results"].each do |r|
        line = "#{MARK.fetch(r['action'], '?')} #{r['resource']} #{r['name']}"
        line += "  #{describe_diff(r['diff'])}" if r["diff"]
        line += r["status"] == "applied" ? "  ok" : "  FAILED: #{r['error']}"
        @out.puts line
      end
      summary = result["summary"]
      @out.puts "Applied #{summary['applied']}, failed #{summary['failed']}, unchanged #{summary['noop']}."
      summary["failed"].to_i.zero? ? 0 : 1
    end

    def export
      @out.puts YAML.dump(client.project_config).sub(/\A---\n/, "")
      0
    end

    # -- inspect / upload / manifest ----------------------------------------

    def inspect_project
      project = client.project
      env = project["environment"]
      storage = project.storage_connection
      plan = project["plan"] || {}
      usage = project["usage"] || {}
      @out.puts "#{project['name']} (#{project.id})"
      @out.puts "  environment: #{env ? env['name'] : 'production'}#{" of #{project['environments'].join(', ')}" if project['environments']}"
      if storage
        @out.puts "  storage:     #{storage['provider']} (#{storage['mode']})#{storage['status'] ? ", #{storage['status']}" : ''}"
      else
        @out.puts "  storage:     none connected"
      end
      if plan["name"]
        used = usage["storage_bytes_used"].to_i
        @out.puts "  plan:        #{plan['name']}, #{human_size(used)} of #{human_size(plan['storage_bytes'].to_i)} used, " \
                  "#{usage['projects_used']} of #{plan['project_limit'] || 'unlimited'} projects"
      end
      @out.puts "  policies:    #{project.upload_policies.map { |p| "#{p.name} (#{p.visibility}, #{human_size(p.maximum_size.to_i)})" }.join(', ').then { _1.empty? ? 'none' : _1 }}"
      @out.puts "  transforms:  #{project.transforms.map(&:name).join(', ').then { _1.empty? ? 'none' : _1 }}"
      0
    end

    def upload
      options = { policy: nil }
      parser = OptionParser.new do |o|
        o.on("--policy NAME") { |v| options[:policy] = v }
        o.on("--content-type TYPE") { |v| options[:content_type] = v }
      end
      paths = parser.parse(@argv)
      path = paths.first
      if path.nil? || options[:policy].nil?
        @err.puts "Usage: file_hutch upload PATH --policy NAME"
        return 2
      end
      unless ::File.file?(path)
        @err.puts "No such file: #{path}"
        return 2
      end

      file = client.upload(path, policy: options[:policy], content_type: options[:content_type])
      @out.puts file.id
      0
    end

    def manifest
      after = nil
      loop do
        page = client.manifest(after: after)
        page.fetch("files").each { |entry| @out.puts JSON.generate(entry) }
        break unless page["has_more"]
        after = page["next_after"]
      end
      0
    end

    # -- helpers ------------------------------------------------------------

    def parse_options
      options = { file: DEFAULT_FILE, prune: false, yes: false }
      parser = OptionParser.new do |o|
        o.on("--prune") { options[:prune] = true }
        o.on("--yes", "-y") { options[:yes] = true }
      end
      rest = parser.parse(@argv)
      options[:file] = rest.first if rest.first
      options
    end

    def read_config(path)
      unless ::File.file?(path)
        @err.puts "No config file at #{path}. Run `file_hutch export > #{DEFAULT_FILE}` to start from what you have."
        return nil
      end
      data = YAML.safe_load(::File.read(path), aliases: true) || {}
      unless data.is_a?(Hash)
        @err.puts "#{path} must be a YAML mapping (uploads:, transforms:, environments:)."
        return nil
      end
      data
    end

    def print_changes(changes)
      changes.each do |c|
        next if c["action"] == "noop"

        line = "#{MARK.fetch(c['action'], '?')} #{c['resource']} #{c['name']}"
        line += "  #{describe_diff(c['diff'])}" if c["diff"]
        @out.puts line
      end
      unchanged = changes.count { |c| c["action"] == "noop" }
      @out.puts "= #{unchanged} unchanged" if unchanged.positive?
    end

    def describe_diff(diff)
      diff.map { |key, (from, to)| "#{key}: #{from.inspect} → #{to.inspect}" }.join(", ")
    end

    def human_size(bytes)
      return "#{bytes} B" if bytes < 1024
      units = %w[KB MB GB TB]
      value = bytes.to_f
      unit = nil
      units.each do |u|
        value /= 1024
        unit = u
        break if value < 1024
      end
      format(value >= 10 ? "%.0f %s" : "%.1f %s", value, unit)
    end
  end
end
