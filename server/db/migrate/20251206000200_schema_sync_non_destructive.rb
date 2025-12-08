class SchemaSyncNonDestructive < ActiveRecord::Migration[7.1]
  def up
    base = File.expand_path('../../..', __dir__) # repo root
    sql_path = File.join(base, 'db', 'migrations', '001_initial.sql')
    raise "Missing schema SQL at #{sql_path}" unless File.file?(sql_path)
    execute File.read(sql_path)
  end

  def down
    # Non-destructive sync has no down; leave schema intact
  end
end
