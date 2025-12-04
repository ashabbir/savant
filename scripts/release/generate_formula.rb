#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'fileutils'

root = File.expand_path('../..', __dir__)
dist = File.join(root, 'dist')
checksums = File.read(File.join(dist, 'checksums.txt')).lines.map(&:strip)

# Parse entries like: SHA256  savant-vX.Y.Z-<os>-<arch>.tar.gz
artifacts = {}
checksums.each do |line|
  next if line.empty?

  sha, filename = line.split(/\s+/, 2)
  next unless filename =~ /savant-(v?\d+\.\d+\.\d+)-(.*)\.tar\.gz/

  version = Regexp.last_match(1)
  osarch = Regexp.last_match(2)
  artifacts[osarch] = { sha: sha, file: filename, version: version }
end

version = artifacts.values.first && artifacts.values.first[:version]
abort 'No artifacts or version detected' unless version

base_url = ENV['RELEASE_BASE_URL'] || 'https://github.com/ashabbir/savant/releases/download'
tag = version.start_with?('v') ? version : "v#{version}"

def url_for(base_url, tag, file)
  File.join(base_url, tag, file)
end

template = <<~RUBY
  class Savant < Formula
    desc "Local MCP services with offline activation"
    homepage "https://github.com/ashabbir/savant"
    version "#{version}"

    on_macos do
      on_arm do
        url "__URL_DARWIN_ARM64__"
        sha256 "__SHA_DARWIN_ARM64__"
      end
      on_intel do
        url "__URL_DARWIN_AMD64__"
        sha256 "__SHA_DARWIN_AMD64__"
      end
    end

    on_linux do
      on_intel do
        url "__URL_LINUX_AMD64__"
        sha256 "__SHA_LINUX_AMD64__"
      end
    end

    def install
      bin.install "savant"
    end

    test do
      assert_match version.to_s, shell_output("#{bin}/savant version")
    end
  end
RUBY

replacements = {
  '__URL_DARWIN_ARM64__' => nil,
  '__SHA_DARWIN_ARM64__' => nil,
  '__URL_DARWIN_AMD64__' => nil,
  '__SHA_DARWIN_AMD64__' => nil,
  '__URL_LINUX_AMD64__' => nil,
  '__SHA_LINUX_AMD64__' => nil
}

{
  'darwin-arm64' => %w[__URL_DARWIN_ARM64__ __SHA_DARWIN_ARM64__],
  'darwin-x86_64' => %w[__URL_DARWIN_AMD64__ __SHA_DARWIN_AMD64__],
  'linux-amd64' => %w[__URL_LINUX_AMD64__ __SHA_LINUX_AMD64__]
}.each do |osarch, (url_key, sha_key)|
  next unless artifacts[osarch]

  file = artifacts[osarch][:file]
  sha = artifacts[osarch][:sha]
  replacements[url_key] = url_for(base_url, tag, file)
  replacements[sha_key] = sha
end

replacements.each do |k, v|
  template = template.gsub(k, v || '""')
end

out_dir = File.join(root, 'packaging', 'homebrew')
FileUtils.mkdir_p(out_dir)
File.write(File.join(out_dir, 'savant.rb'), template)
puts "[formula] Wrote #{File.join(out_dir, 'savant.rb')}"
