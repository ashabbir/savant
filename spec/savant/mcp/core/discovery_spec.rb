# frozen_string_literal: true

require 'spec_helper'
require 'savant/mcp/core/dsl'

RSpec.describe 'DSL dynamic tool loading' do
  let(:tmpdir) { File.join('tmp', 'tools_discovery') }

  before do
    FileUtils.mkdir_p(tmpdir)
    # two files that declare tools using the builder DSL methods
    File.write(File.join(tmpdir, 'a_first.rb'), <<~RB)
      tool 'alpha/one', description: 'one' do |_ctx, _a|
        1
      end
    RB
    File.write(File.join(tmpdir, 'b_second.rb'), <<~RB)
      tool 'beta/two', description: 'two' do |_ctx, _a|
        2
      end
    RB
  end

  after do
    FileUtils.rm_f(File.join(tmpdir, 'a_first.rb'))
    FileUtils.rm_f(File.join(tmpdir, 'b_second.rb'))
    Dir.rmdir(tmpdir) if Dir.exist?(tmpdir)
  end

  it 'registers tools from files in sorted order' do
    reg = Savant::MCP::Core::DSL.build do
      load_dir tmpdir
    end

    names = reg.specs.map { |s| s[:name] }
    expect(names).to eq(['alpha/one', 'beta/two'])
    expect(reg.call('alpha/one', {}, ctx: {})).to eq(1)
    expect(reg.call('beta/two', {}, ctx: {})).to eq(2)
  end
end

