# frozen_string_literal: true

# Periodic cleanup of idle database connections to prevent EMFILE errors
# Runs every 30 minutes in a background thread

Thread.new do
  loop do
    sleep 30.minutes
    begin
      db = Savant::Framework::DB.new
      db.cleanup_idle_connections
      db.close
    rescue StandardError => e
      Rails.logger.warn("Connection cleanup failed: #{e.message}")
    end
  end
end
