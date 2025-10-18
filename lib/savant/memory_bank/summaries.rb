require 'time'
begin
  require 'summarize'
rescue LoadError
  # Optional dependency; we will fall back to heuristic
end

module Savant
  module MemoryBank
    module Summaries
      module_function

      def summarize(text, max_length: 300)
        txt = text.to_s.strip
        return { text: '', length: 0, source: 'none', generated_at: Time.now.utc.iso8601 } if txt.empty?
        # Prefer summarize gem if available
        if defined?(Summarize)
          begin
            out = Summarize.summarize(txt, max_length: max_length).to_s.strip
            if out.nil? || out.empty?
              out = heuristic(txt, max_length)
              src = 'heuristic'
            else
              src = 'summarize'
            end
            return { text: out, length: out.length, source: src, generated_at: Time.now.utc.iso8601 }
          rescue => _e
            # fall through to heuristic
          end
        end
        out = heuristic(txt, max_length)
        { text: out, length: out.length, source: 'heuristic', generated_at: Time.now.utc.iso8601 }
      end

      def heuristic(txt, max_length)
        para = txt.split(/\n\n+/).first.to_s.strip
        para.length > max_length ? para[0, max_length - 1] + '…' : para
      end
    end
  end
end
