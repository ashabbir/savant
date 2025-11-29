#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'

module Savant
  # Lightweight project generator for new MCP engines/tools.
  class Generator
    def initialize(dest_root: Dir.pwd, out: $stdout)
      @root = File.expand_path(dest_root)
      @out = out
    end

    # Generate a new engine skeleton under lib/savant/<name>/
    # Options: { with_db: Boolean, force: Boolean }
    def generate_engine(name, with_db: false, force: false)
      mod = camelize(name)
      base = File.join(@root, 'lib', 'savant', name)
      tools_path = File.join(base, 'tools.rb')
      engine_path = File.join(base, 'engine.rb')
      spec_dir = File.join(@root, 'spec', 'savant', name)
      spec_path = File.join(spec_dir, 'engine_spec.rb')

      ensure_dir(base)
      ensure_dir(spec_dir)

      write_file(engine_path, engine_template(mod, with_db: with_db), force: force)
      write_file(tools_path, tools_template(mod, name), force: force)
      write_file(spec_path, spec_template(mod, name), force: force)

      @out.puts "created: #{engine_path}\ncreated: #{tools_path}\ncreated: #{spec_path}"
      true
    end

    private

    def ensure_dir(path)
      FileUtils.mkdir_p(path)
    end

    def write_file(path, content, force: false)
      raise "file exists: #{path} (use --force to overwrite)" if File.exist?(path) && !force

      File.write(path, content)
    end

    def camelize(s)
      s.split(/[^a-zA-Z0-9]/).map { |p| p.empty? ? '' : p[0].upcase + p[1..] }.join
    end

    def engine_template(mod, with_db: false)
      db_init = with_db ? "\n        @db = Savant::Framework::DB.new\n" : "\n"
      <<~RUBY
        #!/usr/bin/env ruby
        # Engine for Savant::#{mod} MCP service

        module Savant
          module #{mod}
            class Engine
              def initialize
                @log = Savant::Logging::Logger.new(io: $stdout, json: true, service: '#{mod.downcase}.engine')
        #{db_init}                @ops = Object.new # replace with real ops
              end

              def server_info
                { name: 'savant-#{mod.downcase}', version: '1.1.0', description: '#{mod} MCP service' }
              end
            end
          end
        end
      RUBY
    end

    def tools_template(mod, name)
      <<~RUBY
        #!/usr/bin/env ruby
        # Tools registrar for Savant::#{mod}

        require_relative '../framework/mcp/core/dsl'

        module Savant
          module #{mod}
            module Tools
              module_function

              def build_registrar(engine)
                Savant::Framework::MCP::Core::DSL.build do
                  tool '#{name}/hello', description: 'Example hello tool',
                       schema: { type: 'object', properties: { name: { type: 'string' } } } do |_ctx, a|
                    { hello: (a['name'] || 'world') }
                  end
                end
              end
            end
          end
        end
      RUBY
    end

    def spec_template(mod, name)
      <<~RUBY
        # frozen_string_literal: true

        require 'spec_helper'
        require_relative '../../../lib/savant/#{name}/tools'

        RSpec.describe Savant::#{mod}::Tools do
          it 'builds registrar with example tool' do
            engine = double('engine')
            reg = described_class.build_registrar(engine)
            specs = reg.specs
            expect(specs.any? { |s| s[:name] == '#{name}/hello' }).to be(true)
            out = reg.call('#{name}/hello', { 'name' => 'dev' }, ctx: { engine: engine })
            expect(out).to eq({ hello: 'dev' })
          end
        end
      RUBY
    end
  end
end
