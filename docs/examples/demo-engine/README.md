# Demo Engine (Hello)

This example shows how to scaffold a minimal engine using the generator and wire it up for local testing.

## Generate

```bash
bundle exec ruby ./bin/savant generate engine demo --with-db
```

Files created:

- `lib/savant/demo/engine.rb`
- `lib/savant/demo/tools.rb`
- `spec/savant/demo/engine_spec.rb`

## Run (stdio)

```bash
MCP_SERVICE=demo ruby ./bin/mcp_server
```

In another shell:

```bash
ruby ./bin/savant list tools --service=demo
ruby ./bin/savant call 'demo/hello' --service=demo --input='{"name":"dev"}'
```

## Sample Files (generated)

engine.rb

```ruby
#!/usr/bin/env ruby
# Engine for Savant::Demo MCP service

module Savant
  module Demo
    class Engine
      def initialize
        @log = Savant::Logger.new(io: $stdout, json: true, service: 'demo.engine')
        @ops = Object.new # replace with real ops
      end

      def server_info
        { name: 'savant-demo', version: '1.1.0', description: 'Demo MCP service' }
      end
    end
  end
end
```

tools.rb

```ruby
#!/usr/bin/env ruby
# Tools registrar for Savant::Demo

require_relative '../../mcp/core/dsl'

module Savant
  module Demo
    module Tools
      module_function

      def build_registrar(engine)
        Savant::MCP::Core::DSL.build do
          tool 'demo/hello', description: 'Example hello tool',
               schema: { type: 'object', properties: { name: { type: 'string' } } } do |_ctx, a|
            { hello: (a['name'] || 'world') }
          end
        end
      end
    end
  end
end
```

spec/savant/demo/engine_spec.rb

```ruby
# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/savant/demo/tools'

RSpec.describe Savant::Demo::Tools do
  it 'builds registrar with example tool' do
    engine = double('engine')
    reg = described_class.build_registrar(engine)
    specs = reg.specs
    expect(specs.any? { |s| s[:name] == 'demo/hello' }).to be(true)
    out = reg.call('demo/hello', { 'name' => 'dev' }, ctx: { engine: engine })
    expect(out).to eq({ hello: 'dev' })
  end
end
```

## Make Targets (optional)

```bash
# Scaffold or refresh the demo engine
make demo-engine

# Run the demo engine (stdio)
make demo-run

# Call the demo tool
make demo-call
```

