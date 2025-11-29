#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require 'json'
require 'fileutils'
require 'securerandom'
require_relative 'runtime_context'
require_relative 'logger'
require_relative 'personas/ops'
require_relative 'think/engine'

module Savant
  # Boot Runtime: Initializes the Savant Engine
  # This is the core initializer that prepares everything required for any agent,
  # workflow, or multiplexer to function.
  # rubocop:disable Metrics/ModuleLength
  module Boot
    class BootError < StandardError; end

    class << self
      # Main boot sequence
      # @param options [Hash] Boot options
      # @option options [String] :persona_name Default persona to load (default: 'savant-engineer')
      # @option options [String] :driver_version Driver prompt version (default: latest)
      # @option options [String] :base_path Base path for Savant (default: SAVANT_PATH or project root)
      # @option options [Boolean] :skip_git Skip git repo detection (default: false)
      # @return [RuntimeContext] Initialized runtime context
      def initialize!(options = {})
        base_path = resolve_base_path(options[:base_path])

        # Initialize logger first
        logger = create_logger(base_path)
        logger.info(event: 'boot_start', session_id: 'initializing')

        begin
          # Generate session ID
          session_id = generate_session_id

          # Load core components
          persona = load_persona(options[:persona_name] || 'savant-engineer', base_path, logger)
          driver_prompt = load_driver_prompt(options[:driver_version], base_path, logger)
          amr_rules = load_amr_rules(base_path, logger)
          repo = options[:skip_git] ? nil : detect_repo_context(logger)
          memory = initialize_memory(base_path, session_id, logger)

          # Create RuntimeContext
          context = RuntimeContext.new(
            session_id: session_id,
            persona: persona,
            driver_prompt: driver_prompt,
            amr_rules: amr_rules,
            repo: repo,
            memory: memory,
            logger: logger,
            multiplexer: nil # Will be set later if needed
          )

          # Set global runtime
          Savant::Runtime.current = context

          # Log boot summary
          log_boot_summary(context, logger)

          # Persist runtime state
          persist_runtime(base_path, context)

          logger.info(event: 'boot_complete', session_id: session_id)
          context
        rescue StandardError => e
          logger.error(event: 'boot_failed', error: e.message, backtrace: e.backtrace.first(5))
          raise BootError, "Boot failed: #{e.message}"
        end
      end

      private

      def resolve_base_path(path = nil)
        return path if path && !path.empty?
        return ENV['SAVANT_PATH'] if ENV['SAVANT_PATH'] && !ENV['SAVANT_PATH'].empty?

        # Default to project root (3 levels up from lib/savant/boot.rb)
        File.expand_path('../../..', __dir__)
      end

      def create_logger(base_path)
        logs_dir = File.join(base_path, 'logs')
        FileUtils.mkdir_p(logs_dir)
        log_file = File.join(logs_dir, 'engine_boot.log')

        Savant::Logger.new(
          io: $stdout,
          file_path: log_file,
          level: ENV['LOG_LEVEL'] || 'info',
          json: true,
          service: 'boot'
        )
      end

      def generate_session_id
        "session_#{Time.now.utc.strftime('%Y%m%d_%H%M%S')}_#{SecureRandom.hex(4)}"
      end

      # Load persona from personas engine
      def load_persona(name, base_path, logger)
        logger.info(event: 'loading_persona', name: name)

        ops = Savant::Personas::Ops.new(root: base_path)
        persona_data = ops.get(name: name)

        result = {
          name: persona_data[:name],
          version: persona_data[:version],
          summary: persona_data[:summary],
          prompt_md: persona_data[:prompt_md],
          tags: persona_data[:tags]
        }

        logger.info(event: 'persona_loaded', name: name, version: result[:version])
        result
      rescue StandardError => e
        logger.error(event: 'persona_load_failed', name: name, error: e.message)
        raise BootError, "Failed to load persona '#{name}': #{e.message}"
      end

      # Load driver prompt from Think engine
      def load_driver_prompt(version, base_path, logger)
        logger.info(event: 'loading_driver_prompt', version: version || 'latest')

        engine = Savant::Think::Engine.new(env: { 'SAVANT_PATH' => base_path })
        prompt_data = engine.driver_prompt(version: version)

        result = {
          version: prompt_data[:version],
          hash: prompt_data[:hash],
          prompt_md: prompt_data[:prompt_md]
        }

        logger.info(event: 'driver_prompt_loaded', version: result[:version], hash: result[:hash])
        result
      rescue StandardError => e
        logger.error(event: 'driver_prompt_load_failed', error: e.message)
        raise BootError, "Failed to load driver prompt: #{e.message}"
      end

      # Load AMR rules from YAML
      def load_amr_rules(base_path, logger)
        logger.info(event: 'loading_amr_rules')

        amr_path = File.join(base_path, 'lib', 'savant', 'amr', 'rules.yml')
        raise BootError, "AMR rules file not found at #{amr_path}. Please create lib/savant/amr/rules.yml" unless File.exist?(amr_path)

        data = YAML.safe_load(File.read(amr_path), permitted_classes: [], aliases: true)

        result = {
          version: data['version'],
          description: data['description'],
          rules: data['rules'] || []
        }

        logger.info(event: 'amr_rules_loaded', version: result[:version], rule_count: result[:rules].size)
        result
      rescue Psych::SyntaxError => e
        logger.error(event: 'amr_rules_parse_failed', error: e.message)
        raise BootError, "Failed to parse AMR rules: #{e.message}"
      rescue StandardError => e
        logger.error(event: 'amr_rules_load_failed', error: e.message)
        raise BootError, "Failed to load AMR rules: #{e.message}"
      end

      # Detect git repository context
      def detect_repo_context(logger)
        logger.info(event: 'detecting_repo')

        # Try to find .git directory
        current_dir = Dir.pwd
        repo_root = find_git_root(current_dir)

        unless repo_root
          logger.warn(event: 'no_repo_found')
          return nil
        end

        # Get current branch
        branch = `git -C "#{repo_root}" rev-parse --abbrev-ref HEAD 2>/dev/null`.strip

        # Get last commit (optional)
        last_commit = `git -C "#{repo_root}" rev-parse --short HEAD 2>/dev/null`.strip

        result = {
          path: repo_root,
          branch: branch.empty? ? nil : branch,
          last_commit: last_commit.empty? ? nil : last_commit
        }

        logger.info(event: 'repo_detected', path: repo_root, branch: result[:branch])
        result
      rescue StandardError => e
        logger.warn(event: 'repo_detection_failed', error: e.message)
        nil
      end

      def find_git_root(start_path)
        current = File.expand_path(start_path)

        loop do
          git_dir = File.join(current, '.git')
          return current if File.directory?(git_dir)

          parent = File.dirname(current)
          break if parent == current # Reached root

          current = parent
        end

        nil
      end

      # Initialize session memory system
      def initialize_memory(base_path, session_id, logger)
        logger.info(event: 'initializing_memory', session_id: session_id)

        # Create .savant directory
        savant_dir = File.join(base_path, '.savant')
        FileUtils.mkdir_p(savant_dir)

        # Initialize memory structure
        memory = {
          ephemeral: {}, # In-RAM memory
          persistent_path: File.join(savant_dir, 'runtime.json'),
          session_id: session_id,
          created_at: Time.now.utc.iso8601
        }

        logger.info(event: 'memory_initialized', path: memory[:persistent_path])
        memory
      rescue StandardError => e
        logger.error(event: 'memory_init_failed', error: e.message)
        raise BootError, "Failed to initialize memory: #{e.message}"
      end

      # Log boot summary
      def log_boot_summary(context, logger)
        logger.info(
          event: 'boot_summary',
          session_id: context.session_id,
          persona_name: context.persona[:name],
          persona_version: context.persona[:version],
          driver_version: context.driver_prompt[:version],
          amr_rule_count: context.amr_rules[:rules].size,
          repo_path: context.repo&.dig(:path),
          repo_branch: context.repo&.dig(:branch)
        )
      end

      # Persist runtime state to .savant/runtime.json
      def persist_runtime(base_path, context)
        runtime_file = File.join(base_path, '.savant', 'runtime.json')

        runtime_state = {
          session_id: context.session_id,
          persona: {
            name: context.persona[:name],
            version: context.persona[:version]
          },
          driver_prompt: {
            version: context.driver_prompt[:version],
            hash: context.driver_prompt[:hash]
          },
          amr: {
            version: context.amr_rules[:version],
            rule_count: context.amr_rules[:rules].size
          },
          repo: context.repo,
          created_at: context.memory[:created_at],
          updated_at: Time.now.utc.iso8601
        }

        File.write(runtime_file, JSON.pretty_generate(runtime_state))
        context.logger.info(event: 'runtime_persisted', path: runtime_file)
      rescue StandardError => e
        context.logger.warn(event: 'runtime_persist_failed', error: e.message)
        # Don't fail boot if persistence fails
      end
    end
  end
  # rubocop:enable Metrics/ModuleLength
end
