# frozen_string_literal: true

module Ridgepole
  module ExtTidb
    module DumpPatch
      def dump(*args)
        dsl = super

        conn = ActiveRecord::Base.connection
        return dsl unless conn.respond_to?(:tidb?) && conn.tidb?

        begin
          tables = conn.tables
        rescue StandardError
          return dsl
        end

        tables.each do |table|
          extras = extract_table_auto_random_options_for_dump(conn, table)
          next if extras.empty?

          # inject into create_table line
          dsl = inject_table_options_line(dsl, table, extras)
        end

        dsl
      end

      private

      def extract_table_auto_random_options_for_dump(conn, table)
        extras = {}
        begin
          row = conn.execute("SHOW CREATE TABLE #{conn.quote_table_name(table)}").first
          create_sql = row[1] if row
          return extras unless create_sql

          if (m = create_sql.match(/AUTO_RANDOM\((\d+)\)/i))
            extras[:auto_random] = m[1].to_i
          end
          if (m = create_sql.match(/AUTO_RANDOM_BASE=(\d+)/i))
            extras[:auto_random_base] = m[1].to_i
          end
        rescue StandardError
        end
        extras
      end

      def inject_table_options_line(dsl, table, extras)
        keyvals = []
        keyvals << "auto_random: #{extras[:auto_random]}" if extras[:auto_random]
        keyvals << "auto_random_base: #{extras[:auto_random_base]}" if extras[:auto_random_base]
        return dsl if keyvals.empty?

        pattern = /(^(\s*)create_table\s+"#{Regexp.escape(table)}",\s*)(.+?)(\s+do\s*\|t\|)/m
        dsl.sub(pattern) do
          head = Regexp.last_match(1)
          indent = Regexp.last_match(2)
          opts = Regexp.last_match(3)
          tail = Regexp.last_match(4)

          # 既に同キーがあるなら上書きはせずそのまま
          already = keyvals.any? { |kv| opts.include?(kv.split(':').first + ':') }
          if already
            head + opts + tail
          else
            injected = keyvals.join(', ')
            # id: が先頭にあるならその直後に差し込む。なければ先頭に追加。
            if opts =~ /(id:\s*[^,]+,\s*)/i
              head + opts.sub($1, "#{$1}#{injected}, ") + tail
            else
              head + "#{injected}, " + opts + tail
            end
          end
        end
      end
    end
  end
end

