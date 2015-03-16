# Copyright (c) 2006-2010, Gerardo Santana Gomez Garrido <gerardo.santana@gmail.com>
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. The name of the author may not be used to endorse or promote products
#    derived from this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT,
# INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
# STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
# ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

require 'active_record/connection_adapters/abstract_adapter'
require 'arel/visitors/informix'
require 'arel/visitors/bind_visitor'
require 'informix' unless self.class.const_defined?(:Informix)

module Informix

    #
    # <tt>Informix::Result</tt> is a class needed to make sense out of the
    # <tt>Informix#cursor()</tt> return value and adjust it in a way
    # that is palatable to <tt>ActiveRecord::Result</tt> objects, namely
    # to carry the +fields+ and the +to_a+ methods properly
    #
    class Result

      include Enumerable

      attr_reader :cursor_result

      #
      # +cursor_result+ must be in the form of an array of hashes
      # in which each hash represents a row returned by the database.
      # The hash has the fields names as keys and the vaules for that row as
      # values.
      #
      # Trivial Example:
      #
      # <tt>
      #    cursor_results = [{ "COUNT(*) => 33" }]
      #    ir = Informix::Result.new(cursor_results)
      #    ir.fields => ["COUNT(*)"]
      #    ir.values => [33]
      # </tt>
      #
      def initialize(cr)
        @cursor_result = cr
      end

      def fields
        res = []
        return res if self.cursor_result.empty?
        res = self.cursor_result.first.keys
      end

      def to_a
        self.cursor_result.map { |row| row.values }
      end

    end
end

module ActiveRecord
  class Base
    def self.informix_connection(config) #:nodoc:
      require 'informix' unless self.class.const_defined?(:Informix)
      require 'stringio'
      
      config = config.symbolize_keys

      database    = config[:database].to_s
      username    = config[:username]
      password    = config[:password]
      db          = Informix.connect(database, username, password)
      return_adapter(db, config)
    end

    after_save :write_lobs
    private

      def self.return_adapter(db, config)
        ConnectionAdapters::InformixAdapter.new(db, logger, config)
      end

      def write_lobs
        return if !self.class.connection.is_a?(ConnectionAdapters::InformixAdapter)
        self.class.columns.each do |c|
          value = self[c.name]
          next if (![:text, :binary].include? c.type) || value.nil? || value == ''
          connection.raw_connection.execute(<<-end_sql, StringIO.new(value))
              UPDATE #{self.class.table_name} SET #{c.name} = ?
              WHERE #{self.class.primary_key} = #{quote_value(id)}
          end_sql
        end
      end
  end # class Base

  module ConnectionAdapters
    class InformixColumn < Column
      def initialize(column)
        sql_type = make_type(column[:stype], column[:length],
                             column[:precision], column[:scale])
        super(column[:name], column[:default], sql_type, column[:nullable])
      end

      private
        IFX_TYPES_SUBSET = %w(CHAR CHARACTER CHARACTER\ VARYING DECIMAL FLOAT
                              LIST LVARCHAR MONEY MULTISET NCHAR NUMERIC
                              NVARCHAR SERIAL SERIAL8 VARCHAR).freeze

        def make_type(type, limit, prec, scale)
          type.sub!(/money/i, 'DECIMAL')
          if IFX_TYPES_SUBSET.include? type.upcase
            if prec == 0
              "#{type}(#{limit})" 
            else
              "#{type}(#{prec},#{scale})"
            end
          elsif type =~ /datetime/i
            type = "time" if prec == 6
            type
          elsif type =~ /byte/i
            "binary"
          else
            type
          end
        end

        def simplified_type(sql_type)
          if sql_type =~ /serial/i
            :primary_key
          else
            super
          end
        end
    end

    # This adapter requires Ruby/Informix
    # http://ruby-informix.rubyforge.org
    #
    # Options:
    #
    # * <tt>:database</tt>  -- Defaults to nothing.
    # * <tt>:username</tt>  -- Defaults to nothing.
    # * <tt>:password</tt>  -- Defaults to nothing.

    class InformixAdapter < AbstractAdapter

      attr_reader :last_return_value

      class BindSubstitution < Arel::Visitors::Informix # :nodoc:
        include Arel::Visitors::BindVisitor
      end

      def initialize(db, logger, config)
        super(db, logger)

        @ifx_version = db.version.major.to_i

        #
        # We basically avoid +prepared_statements+ because we can't find
        # documentation on what they are (we *suppose* something, but that's
        # simply not enough down here) and how to implement them in
        # +Informix+. However, they can be set to true in the configuration,
        # so you may want to test them by setting:
        #
        #     prepared_statements:  true
        #
        # in the database configuration
        #
        if config.fetch(:prepared_statements) { false }
          @visitor = Arel::Visitors::Informix.new self
        else
          @visitor = BindSubstitution.new self
        end

        @config = config
      end

      def native_database_types
        {
          :primary_key => "serial primary key",
          :string      => { :name => "varchar", :limit => 255  },
          :text        => { :name => "text" },
          :integer     => { :name => "integer" },
          :float       => { :name => "float" },
          :decimal     => { :name => "decimal" },
          :datetime    => { :name => "datetime year to second" },
          :timestamp   => { :name => "datetime year to second" },
          :time        => { :name => "datetime hour to second" },
          :date        => { :name => "date" },
          :binary      => { :name => "byte"},
          :boolean     => { :name => "boolean"}
        }
      end

      def adapter_name
        'Informix'
      end

      #
      # FIXME: in the very specific case of DDS we are not using the "_seq"
      # scheme at all so we don't want to prefetch primary keys at any time.
      # This is combined with the fact that the +composite_primary_keys+ gem
      # does not support auto-incrementing sequences.
      #
      def prefetch_primary_key?(table_name = nil)
        false
      end
 
      def supports_migrations? #:nodoc:
        true
      end

      def default_sequence_name(table, column) #:nodoc:
        "#{table}_seq"
      end

      def set_isolation #:nodoc:
        "SET ISOLATION TO DIRTY READ"
      end

      # DATABASE STATEMENTS =====================================

      def real_execute(sql, name = nil)
        @last_return_value = @connection.immediate(sql)
        nil
      end

      def exec_query_with_no_return_value(sql, name = nil, binds = [])
        log(sql, name, binds) do
          real_execute(sql, name)
        end
      end

      alias_method :execute, :exec_query_with_no_return_value

      def get_cursor(sql, name = nil, binds = [])
        log(sql, name, binds) do
          cursor = @connection.cursor(sql)
          yield(cursor) if block_given?
          cursor.free
        end
      end

      def exec_query_with_return_value(sql, name = nil, binds = [])
        result = nil
        get_cursor(sql, name, binds) do
          |cursor|
          result = Informix::Result.new(cursor.open.fetch_hash_all)
        end
        ActiveRecord::Result.new(result.fields, result.to_a) if result
      end

      def select_rows(sql, name = nil, binds = [])
        rows = []
        get_cursor(sql, name, binds) do
          |cursor|
          rows = cursor.open.fetch_hash_all
        end
        rows
      end

      alias_method :exec_update, :exec_query_with_no_return_value
      alias_method :exec_delete, :exec_query_with_no_return_value
      alias_method :exec_insert, :exec_query_with_no_return_value

      def insert(arel, name = nil, pk = nil, id_value = nil, sequence_name = nil, binds = [])
        exec_insert(to_sql(arel, binds), name, binds)
      end

      def update(arel, name = nil, binds = [])
        exec_update(to_sql(arel, binds), name, binds)
      end

      def delete(arel, name = nil, binds = [])
        exec_delete(to_sql(arel, binds), name, binds)
      end

      def prepare(sql, name = nil, binds = [])
        log(sql, name, binds) do
          @connection.prepare(sql)
        end
      end

      def last_inserted_id(result)
        nil
      end

      def supports_transaction_isolation?
        true
      end

      def begin_isolated_db_transaction(not_used)
        exec_query_with_no_return_value(set_isolation)
        begin_db_transaction
      end

      def begin_db_transaction
        exec_query_with_no_return_value("BEGIN WORK")
      end

      def commit_db_transaction
        exec_query_with_no_return_value("COMMIT WORK")
        @connection.commit
      end

      def rollback_db_transaction
        exec_query_with_no_return_value("ROLLBACK WORK")
        @connection.rollback
      end
      
      def primary_key(table_name) #:nodoc:
        res = nil
        @connection.cursor(<<-end_sql) do |cur|
            SELECT FIRST 1 ct.constrname FROM sysconstraints ct, systables st WHERE st.tabid = ct.tabid AND ct.constrtype = 'P' AND st.tabname = '#{table_name}'
          end_sql
          rows = cur.open.fetch
          res = rows.first if rows
        end
        res
      end

      def next_sequence_value(sequence_name)
        exec_query_with_return_value("select #{sequence_name}.nextval id from systables where tabid=1")['id']
      end

      # QUOTING ===========================================
      def quote_string(string)
        string.gsub(/\'/, "''")
      end

      def quote(value, column = nil)
        if column && [:binary, :text].include?(column.type)
          return "NULL"
        end
        if column && column.type == :date
          return "'#{value.mon}/#{value.day}/#{value.year}'"
        end
        super
      end

      # SCHEMA STATEMENTS =====================================
      def tables(name = nil)
        @connection.cursor(<<-end_sql) do |cur|
            SELECT tabname FROM systables WHERE tabid > 99 AND tabtype != 'Q'
          end_sql
          cur.open.fetch_all.flatten
        end
      end

      def columns(table_name, name = nil)
        @connection.columns(table_name).map {|col| InformixColumn.new(col) }
      end

      # MIGRATION =========================================
      #
      # These calls cannot be done from an open connection, so they
      # won't work in any case.
      #
#     def recreate_database(name)
#       drop_database(name)
#       create_database(name)
#     end

#     def drop_database(name)
#       exec_query_with_no_return_value("drop database #{name}")
#     end

#     def create_database(name)
#       exec_query_with_no_return_value("create database #{name}")
#     end

      def create_table(name, options = {})
        super(name, options)
        execute("CREATE SEQUENCE #{name}_seq")
      end

      def drop_table(name, options = {})
        super(name, options)
        execute("DROP SEQUENCE #{name}_seq")
      end

      # XXX
      def indexes(table_name, name = nil)
        indexes = []
      end
            
      def rename_column(table, column, new_column_name)
        exec_query_with_no_return_value("RENAME COLUMN #{table}.#{column} TO #{new_column_name}")
      end
      
      def change_column(table_name, column_name, type, options = {}) #:nodoc:
        sql = "ALTER TABLE #{table_name} MODIFY #{column_name} #{type_to_sql(type, options[:limit])}"
        add_column_options!(sql, options)
        exec_query_with_no_return_value(sql)
      end

      def remove_index(table_name, options = {})
        exec_query_with_no_return_value("DROP INDEX #{index_name(table_name, options)}")
      end

      def delete(dstmt, name = nil, binds = [])
        exec_query_with_no_return_value(to_sql(dstmt, binds), name, binds)
      end

      protected

      def select(sql, name = nil, binds = [])
        exec_query_with_return_value(sql, name, binds)
      end

    end #class InformixAdapter < AbstractAdapter


  end #module ConnectionAdapters

end #module ActiveRecord
