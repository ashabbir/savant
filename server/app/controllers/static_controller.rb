#!/usr/bin/env ruby
# frozen_string_literal: true

class StaticController < ApplicationController
  # Respond to default browser favicon requests to avoid noisy 404s during dev.
  # We intentionally return no content with a cache header; teams can drop a
  # real icon into server/public/favicon.ico later without code changes.
  def favicon
    response.headers['Cache-Control'] = 'public, max-age=86400'
    head :no_content
  end
end

