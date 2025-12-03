#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'digest'
require 'fileutils'
require 'socket'

module Savant
  module Framework
    module License
      class Error < StandardError; end

      module_function

      # Location of the local activation file
      # Override for tests or custom setups with SAVANT_LICENSE_PATH
      def path
        env_path = ENV['SAVANT_LICENSE_PATH']
        return env_path unless env_path.nil? || env_path.empty?

        home = Dir.home rescue '.'
        File.join(home, '.savant', 'license.json')
      end

      # Return the salt from env or a development default
      def secret_salt
        (ENV['SAVANT_SECRET_SALT'] && !ENV['SAVANT_SECRET_SALT'].empty?) ? ENV['SAVANT_SECRET_SALT'] : 'DEVELOPMENT_ONLY_CHANGE_ME'
      end

      # Compute the expected key for a username
      def expected_key(username)
        Digest::SHA256.hexdigest("#{username}#{secret_salt}")
      end

      # Read current license file (or nil if missing)
      def read
        p = path
        return nil unless File.file?(p)

        data = JSON.parse(File.read(p))
        { username: data['username'], key: data['key'], activated_at: data['activated_at'], host: data['host'] }
      rescue JSON::ParserError
        nil
      end

      # Write/activate license given username and key
      def activate!(username:, key:)
        dir = File.dirname(path)
        FileUtils.mkdir_p(dir)
        rec = { 'username' => username, 'key' => key, 'activated_at' => Time.now.utc.iso8601, 'host' => Socket.gethostname rescue 'unknown' }
        File.write(path, JSON.pretty_generate(rec))
        status
      end

      # Delete local license
      def deactivate!
        FileUtils.rm_f(path)
        true
      end

      # Boolean validity with reason
      def valid?
        s = status
        [s[:valid], s[:reason]]
      end

      # Return detailed status
      def status
        return { valid: true, reason: 'dev_bypass', path: nil, username: nil } if dev_bypass?

        cur = read
        return { valid: false, reason: 'missing_file', path: path, username: nil } unless cur

        username = cur[:username]
        key = cur[:key]
        return { valid: false, reason: 'missing_fields', path: path, username: username } if username.to_s.empty? || key.to_s.empty?

        exp = expected_key(username)
        ok = (key == exp)
        { valid: ok, reason: ok ? 'ok' : 'mismatch', path: path, username: username }
      end

      # Raise if invalid (unless dev bypass)
      def verify!
        v, reason = valid?
        return true if v

        raise Error, "License validation failed (reason=#{reason}). Run: savant activate <username>:<key>"
      end

      def dev_bypass?
        val = ENV['SAVANT_DEV']
        val && !val.empty? && (val == '1' || val.casecmp('true').zero?)
      end
    end
  end
end
