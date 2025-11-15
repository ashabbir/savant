# frozen_string_literal: true

module Support
  class FakeDB
    attr_reader :repos, :blobs, :files, :chunks, :mapped

    def initialize
      @repos = {}
      @blobs = {}
      @files = {}
      @chunks = Hash.new { |h, k| h[k] = [] }
      @mapped = {}
      @next_id = 1
      @tx_depth = 0
      @deleted_all = false
      @deleted_repos = []
    end

    def with_transaction
      @tx_depth += 1
      yield
    ensure
      @tx_depth -= 1
    end

    def find_or_create_repo(name, root)
      @repos[name] ||= begin
        id = next_id
        { 'id' => id, 'root' => root }
        id
      end
    end

    def find_or_create_blob(hash, byte_len)
      @blobs[hash] ||= begin
        id = next_id
        { 'id' => id, 'len' => byte_len }
        id
      end
    end

    def replace_chunks(blob_id, chunks)
      @chunks[blob_id] = chunks.dup
      true
    end

    def upsert_file(repo_id, *args)
      # Support both signatures:
      # upsert_file(repo_id, rel_path, size_bytes, mtime_ns)
      # upsert_file(repo_id, repo_name, rel_path, size_bytes, mtime_ns)
      if args.length == 4
        _repo_name, rel_path, _size_bytes, _mtime_ns = args
      else
        rel_path, _size_bytes, _mtime_ns = args
      end
      key = [repo_id, rel_path]
      @files[key] ||= next_id
      @files[key]
    end

    def map_file_to_blob(file_id, blob_id)
      @mapped[file_id] = blob_id
      true
    end

    def delete_missing_files(_repo_id, kept)
      # no-op for fake, could simulate by pruning @files keys not in kept
      @kept = kept
      true
    end

    def delete_all_data
      @deleted_all = true
      true
    end

    def deleted_all?
      @deleted_all
    end

    def delete_repo_by_name(name)
      @deleted_repos << name
      0
    end

    def deleted_repos
      @deleted_repos.dup
    end

    private

    def next_id
      id = @next_id
      @next_id += 1
      id
    end
  end
end
