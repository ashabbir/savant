# frozen_string_literal: true

require 'fileutils'

# Ensure the server/logs directory exists so Rails can write there.
FileUtils.mkdir_p(Rails.root.join('logs'))

