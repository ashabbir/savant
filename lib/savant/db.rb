require 'pg'

module Savant
  class DB
    def initialize(url = ENV['DATABASE_URL'])
      @url = url
      @conn = PG.connect(@url)
    end

    def close
      @conn.close if @conn
    end

    def migrate_connection_only
      @conn.exec('SELECT 1')
      true
    end
  end
end

