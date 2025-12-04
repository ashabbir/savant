# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Savant::Framework::License do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:license_path) { File.join(tmp_dir, 'license.json') }

  before do
    ENV['SAVANT_LICENSE_PATH'] = license_path
    ENV['SAVANT_SECRET_SALT'] = 'test_salt'
    ENV.delete('SAVANT_DEV')
    FileUtils.rm_f(license_path)
  end

  after do
    FileUtils.rm_f(license_path)
    ENV.delete('SAVANT_LICENSE_PATH')
    ENV.delete('SAVANT_SECRET_SALT')
    ENV.delete('SAVANT_DEV')
    FileUtils.remove_entry(tmp_dir) if File.directory?(tmp_dir)
  end

  it 'computes expected key deterministically' do
    key1 = described_class.expected_key('alice')
    key2 = described_class.expected_key('alice')
    expect(key1).to eq(key2)
    expect(key1.length).to eq(64)
  end

  it 'activates and validates a correct license' do
    user = 'alice'
    key = described_class.expected_key(user)
    st = described_class.activate!(username: user, key: key)
    expect(File).to exist(license_path)
    expect(st[:valid]).to be(true)
    expect(st[:username]).to eq(user)
    expect { described_class.verify! }.not_to raise_error
  end

  it 'rejects an invalid key' do
    described_class.activate!(username: 'bob', key: 'bad')
    v, reason = described_class.valid?
    expect(v).to be(false)
    expect(reason).to eq('mismatch')
    expect { described_class.verify! }.to raise_error(Savant::Framework::License::Error)
  end

  it 'bypasses validation in dev mode' do
    ENV['SAVANT_DEV'] = '1'
    expect { described_class.verify! }.not_to raise_error
  end
end
