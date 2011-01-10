require 'active_record/connection_adapters/abstract_adapter'
require 'active_support/core_ext/kernel/requires'
require 'active_support/core_ext/object/blank'
require 'set'

require 'dstore'
require 'arel/visitors/datastore'

module ActiveRecord
  class Base
    def self.datastore_connection(config) # :nodoc:
      ConnectionAdapters::DatastoreAdapter.new( Dstore::DB.new( config.symbolize_keys ), logger )
    end
  end

  module ConnectionAdapters
    class DatastoreAdapter < AbstractAdapter
      ADAPTER_NAME = "Datastore"

      def adapter_name #:nodoc:
        ADAPTER_NAME
      end
      
      def supports_migrations? #:nodoc:
        true
      end

      def supports_primary_key? #:nodoc:
        true
      end

      def supports_autoincrement? #:nodoc:
        true
      end

      def native_database_types #:nodoc:
        {
          :primary_key => { :name => "integer", :primary_key => true },
          :string      => { :name => "varchar", :limit => 255 },
          :text        => { :name => "text" },
          :integer     => { :name => "integer" },
          :float       => { :name => "float" },
          :decimal     => { :name => "decimal" },
          :datetime    => { :name => "datetime" },
          :timestamp   => { :name => "datetime" },
          :time        => { :name => "time" },
          :date        => { :name => "date" },
          :binary      => { :name => "blob" },
          :boolean     => { :name => "boolean" }
        }
      end

      def select( sql, name = nil, binds = [] )
        log( sql.inspect, name ) {
          @connection.select_query( sql.q, sql.options )
        }
      end

      def insert(sql, name = nil, pk = nil, id_value = nil, sequence_name = nil)
        log( "Insert: " + sql.inspect, name ){
          @connection.insert_query( sql )
        }
      end

      def update( sql, name = nil)
        log( "Update: VALUES(#{sql.options[:values].collect{|k,v|k.to_s + " = " + v.inspect}.join(", ")}) " + sql.inspect, name ) {
          @connection.update_query( sql.q, sql.options[:values] )
        }
      end
      
      def delete(sql, name = nil)
        log( "Delete: " + sql.inspect, name ) {
          @connection.delete_query( sql.q )
        }
      end


      def execute(sql, name = nil)
        log(sql, name) {
          #@connection.execute( sql )
        } 
      end

      def create_table( table_name, options = {} )
        log( "CREATE TABLE #{table_name}", "Datastore Adapter" ) {
          td = TableDefinition.new(self)
          td.primary_key(options[:primary_key] || Base.get_primary_key(table_name.to_s.singularize)) unless options[:id] == false

          yield td if block_given?

          fields = {}
          td.columns.each{|c| fields[c.name.to_s] = { :default => c.default, :type => c.type, :null => c.null } }
          @connection.create_table( table_name, fields )
          td
        }
      end

      def tables
        @connection.tables.keys
      end

      def columns( table_name, name = nil)
        @connection.columns( table_name, name ).collect{|k,opt|
          Column.new( k, opt[:default], opt[:type] == :primary_key ? "integer" : opt[:type], opt[:null] )
        } 
      end
      
      def primary_key( table_name )
        'id'
      end

    end
  end
end
