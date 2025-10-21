# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../../lib/savant/generator'

RSpec.describe Savant::Generator do
  it 'scaffolds a new engine with tools and spec (no db)' do
    Dir.mktmpdir do |dir|
      gen = described_class.new(dest_root: dir, out: StringIO.new)
      ok = gen.generate_engine('abc', with_db: false, force: false)
      expect(ok).to be(true)

      engine = File.join(dir, 'lib', 'savant', 'abc', 'engine.rb')
      tools = File.join(dir, 'lib', 'savant', 'abc', 'tools.rb')
      spec = File.join(dir, 'spec', 'savant', 'abc', 'engine_spec.rb')
      [engine, tools, spec].each { |p| expect(File).to exist(p) }
      expect(File.read(tools)).to include("tool 'abc/hello'")
      expect(File.read(engine)).not_to include('@db = Savant::DB.new')
    end
  end

  it 'supports --with-db to include DB injection' do
    Dir.mktmpdir do |dir|
      gen = described_class.new(dest_root: dir, out: StringIO.new)
      gen.generate_engine('svc', with_db: true)
      engine = File.join(dir, 'lib', 'savant', 'svc', 'engine.rb')
      expect(File.read(engine)).to include('@db = Savant::DB.new')
    end
  end

  it 'refuses to overwrite without --force' do
    Dir.mktmpdir do |dir|
      gen = described_class.new(dest_root: dir, out: StringIO.new)
      gen.generate_engine('dup')
      expect do
        gen.generate_engine('dup')
      end.to raise_error(/file exists/)
    end
  end
end
