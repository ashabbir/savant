namespace :savant do
  desc 'Setup: migrate + ensure FTS + index all'
  task :setup => :environment do
    Rake::Task['db:migrate'].invoke
    require 'savant/framework/db'
    Savant::Framework::DB.new.ensure_fts
    Rake::Task['savant:index_all'].invoke
  end
  desc 'Index all repos (reads config/settings.json)'
  task :index_all => :environment do
    require 'savant/engines/context/fs/repo_indexer'
    require 'savant/framework/db'
    logger = Savant::Logging::Logger.new(io: $stdout, json: false, service: 'savant.index')
    db = Savant::Framework::DB.new
    settings = File.join(SavantRails::SavantContainer.base_path, 'config', 'settings.json')
    indexer = Savant::Context::FS::RepoIndexer.new(db: db, logger: logger, settings_path: settings)
    res = indexer.index(repo: nil, verbose: true)
    puts "Indexed: total=#{res[:total]} changed=#{res[:changed]} skipped=#{res[:skipped]}"
  end

  desc 'Index a single repo by name: rake savant:index[repo_name]'
  task :index, [:repo] => :environment do |_t, args|
    require 'savant/engines/context/fs/repo_indexer'
    require 'savant/framework/db'
    repo = args[:repo]
    abort 'usage: rake savant:index[repo_name]' if repo.to_s.empty?
    logger = Savant::Logging::Logger.new(io: $stdout, json: false, service: 'savant.index')
    db = Savant::Framework::DB.new
    settings = File.join(SavantRails::SavantContainer.base_path, 'config', 'settings.json')
    indexer = Savant::Context::FS::RepoIndexer.new(db: db, logger: logger, settings_path: settings)
    res = indexer.index(repo: repo, verbose: true)
    puts "Indexed repo=#{repo}: total=#{res[:total]} changed=#{res[:changed]} skipped=#{res[:skipped]}"
  end

  desc 'Delete all indexed data'
  task :delete_all => :environment do
    require 'savant/engines/context/fs/repo_indexer'
    require 'savant/framework/db'
    logger = Savant::Logging::Logger.new(io: $stdout, json: false, service: 'savant.index')
    db = Savant::Framework::DB.new
    settings = File.join(SavantRails::SavantContainer.base_path, 'config', 'settings.json')
    indexer = Savant::Context::FS::RepoIndexer.new(db: db, logger: logger, settings_path: settings)
    res = indexer.delete(repo: nil)
    puts "Deleted: deleted=#{res[:deleted]} count=#{res[:count]}"
  end

  desc 'Delete a single repo by name: rake savant:delete[repo_name]'
  task :delete, [:repo] => :environment do |_t, args|
    require 'savant/engines/context/fs/repo_indexer'
    require 'savant/framework/db'
    repo = args[:repo]
    abort 'usage: rake savant:delete[repo_name]' if repo.to_s.empty?
    logger = Savant::Logging::Logger.new(io: $stdout, json: false, service: 'savant.index')
    db = Savant::Framework::DB.new
    settings = File.join(SavantRails::SavantContainer.base_path, 'config', 'settings.json')
    indexer = Savant::Context::FS::RepoIndexer.new(db: db, logger: logger, settings_path: settings)
    res = indexer.delete(repo: repo)
    puts "Deleted repo=#{repo}: deleted=#{res[:deleted]} count=#{res[:count]}"
  end

  desc 'Show status per repo'
  task :status => :environment do
    require 'savant/engines/context/fs/repo_indexer'
    require 'savant/framework/db'
    logger = Savant::Logging::Logger.new(io: $stdout, json: false, service: 'savant.index')
    db = Savant::Framework::DB.new
    settings = File.join(SavantRails::SavantContainer.base_path, 'config', 'settings.json')
    indexer = Savant::Context::FS::RepoIndexer.new(db: db, logger: logger, settings_path: settings)
    rows = indexer.status
    puts "Repos=#{rows.length}"
    rows.each do |r|
      puts "repo=#{r['name']} files=#{r['files']} blobs=#{r['blobs']} chunks=#{r['chunks']} last_mtime=#{r['last_mtime'] || '-'}"
    end
  end
end
