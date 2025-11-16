# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'yaml'

require 'savant/audit/policy'

RSpec.describe Savant::Audit::Policy do
  describe '.load' do
    it 'merges defaults and exposes helpers' do
      file = Tempfile.new('policy.yml')
      file.write({ 'sandbox' => true, 'audit' => { 'enabled' => true, 'store' => 'tmp/audit.json' },
                   'replay' => { 'limit' => 5 } }.to_yaml)
      file.flush

      policy = described_class.load(file.path)

      expect(policy.sandbox?).to be(true)
      expect(policy.audit_enabled?).to be(true)
      expect(policy.audit_store_path).to eq('tmp/audit.json')
      expect(policy.replay_limit).to eq(5)
    ensure
      file.close!
    end
  end

  describe '#enforce!' do
    it 'raises when sandbox prohibits system access' do
      policy = described_class.new('sandbox' => true)
      expect do
        policy.enforce!(tool: 'fs/exec', requires_system: true)
      end.to raise_error(Savant::Audit::Policy::SandboxViolation)
    end

    it 'allows safe operations' do
      policy = described_class.new('sandbox' => true)
      expect(policy.enforce!(tool: 'context/search', requires_system: false)).to eq(true)
    end
  end
end
