# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require_relative '../../lib/savant/engines/think/engine'

RSpec.describe 'Savant::Think::Engine' do
  it 'syncs built-in workflows into the project workflows directory' do
    Dir.mktmpdir('savant-think-test') do |tmp_dir|
      # Prepare Think workflows source
      think_workflows = File.join(tmp_dir, 'lib', 'savant', 'engines', 'think', 'workflows')
      FileUtils.mkdir_p(think_workflows)
      sample_path = File.join(think_workflows, 'sync_test.yaml')
      File.write(sample_path, "steps:\n  - name: test\n")

      # Ensure target directory is missing initially
      workflow_dir = File.join(tmp_dir, 'workflows')
      FileUtils.rm_rf(workflow_dir)

      Savant::Think::Engine.new(env: { 'SAVANT_PATH' => tmp_dir })
      expect(File.exist?(File.join(workflow_dir, 'sync_test.yaml'))).to be true
      expect(File.read(File.join(workflow_dir, 'sync_test.yaml'))).to include('steps')
    end
  end
end
