#!/usr/bin/env ruby
# frozen_string_literal: true

salt = ARGV[0] || ENV['SAVANT_BUILD_SALT'] || 'DEVELOPMENT_ONLY_CHANGE_ME'
root = File.expand_path('../..', __dir__)
out = File.join(root, 'lib', 'savant', 'framework', 'license_salt.rb')

content = <<~RUBY
  #!/usr/bin/env ruby
  # frozen_string_literal: true
  module Savant
    module Framework
      module LicenseSalt
        SECRET_SALT = '#{salt}'.freeze
      end
    end
  end
RUBY

File.write(out, content)
puts "[embed_salt] Wrote #{out}"

