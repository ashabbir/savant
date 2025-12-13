class AddDefaultTimestampsToIndexerTables < ActiveRecord::Migration[7.2]
  def change
    %i[repos files blobs chunks personas rulesets agents agent_runs].each do |table|
      change_column_default table, :created_at, -> { 'NOW()' }
      change_column_default table, :updated_at, -> { 'NOW()' }
    end
  end
end
