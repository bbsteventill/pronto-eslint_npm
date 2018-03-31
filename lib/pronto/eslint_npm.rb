# frozen_string_literal: true

require 'pronto'
require 'shellwords'

module Pronto
  class ESLintNpm < Runner
    CONFIG_FILE = '.pronto_eslint_npm.yml'.freeze
    CONFIG_KEYS = %w[eslint_executable files_to_lint cmd_line_opts].freeze

    attr_writer :eslint_executable, :cmd_line_opts

    def eslint_executable
      @eslint_executable || 'eslint'
    end

    def files_to_lint
      @files_to_lint || /(\.js|\.es6)$/
    end

    def cmd_line_opts
      @cmd_line_opts || ''
    end

    def files_to_lint=(regexp)
      @files_to_lint = regexp.is_a?(Regexp) && regexp || Regexp.new(regexp)
    end

    def config_options
      @config_options ||=
        begin
          config_file = File.join(repo_path, CONFIG_FILE)
          File.exist?(config_file) && YAML.load_file(config_file) || {}
        end
    end

    def read_config
      config_options.each do |key, val|
        next unless CONFIG_KEYS.include?(key.to_s)
        send("#{key}=", val)
      end
    end

    def run
      return [] if !@patches || @patches.count.zero?

      read_config

      @patches
        .select { |patch| patch.additions > 0 }
        .select { |patch| js_file?(patch.new_file_full_path) }
        .map { |patch| inspect(patch) }
        .flatten.compact
    end

    private

    def repo_path
      @repo_path ||= @patches.first.repo.path
    end

    def inspect(patch)
      offences = run_eslint(patch)
      clean_up_eslint_output(offences)
        .map do |offence|
          patch
            .added_lines
            .select { |line| line.new_lineno == offence['line'] }
            .map { |line| new_message(offence, line) }
        end
    end

    def new_message(offence, line)
      path  = line.patch.delta.new_file[:path]
      level = :warning

      Message.new(path, line, level, offence['message'], nil, self.class)
    end

    def js_file?(path)
      files_to_lint =~ path.to_s
    end

    def run_eslint(patch)
      Dir.chdir(repo_path) do
        JSON.parse `#{eslint_command_line(patch.new_file_full_path.to_s)}`
      end
    end

    def eslint_command_line(path)
      "#{eslint_executable} #{cmd_line_opts} #{Shellwords.escape(path)} -f json"
    end

    def clean_up_eslint_output(output)
      # 1. Filter out offences without a warning or error
      # 2. Get the messages for that file
      # 3. Ignore errors without a line number for now
      output
        .select { |offence| offence['errorCount'] + offence['warningCount'] > 0 }
        .map { |offence| offence['messages'] }
        .flatten.select { |offence| offence['line'] }
    end
  end
end
