require 'active_record/connection_adapters/abstract_adapter'
require 'active_support/core_ext/kernel/requires'
require 'active_support/core_ext/object/blank'
require 'set'

# Patch
require 'active_record/datastore_associations_patch'

require 'yaml'
require 'arel/visitors/datastore'

require 'appengine-apis/users'

module ActiveRecord
  class Base
    def self.datastore_connection(config) # :nodoc:
      ConnectionAdapters::DatastoreAdapter.new( ConnectionAdapters::DatastoreAdapter::DB.new( config.symbolize_keys ), logger )
    end
  end

  module ConnectionAdapters

    class DataStoreColumn < Column
      Key = AppEngine::Datastore::Key
      User = AppEngine::Users::User
      Blob = AppEngine::Datastore::Blob

      class << self
        def handle_multi_value v
          v.respond_to?(:count) ? (v.collect { |e| yield e }) : (yield e)
        end
      end
      
      class Multi
        class << self
          attr_accessor :column
          def new *args
            DataStoreColumn.handle_multi_value args do |k|
              k.is_a?(column.klass) ? k : column.klass.new(k)
            end
          end
        end
      end
    
      def multi_class
        unless @checked_for_multi
          @checked_for_multi = true
          m = sql_type.match /\Amulti_(\w+)\z/
          if m
            @multi_class = Multi.dup
            @multi_class.column = DataStoreColumn.new(name, default, m[1], null)
            @multi_class.column.primary = primary
          end
        end
        @multi_class
      end
    
      def klass
        return multi_class if multi_class

        case sql_type
        when 'blob' then Blob
        when 'user' then User
        when 'key' then Key
        else super
        end
      end
      
      def type_cast(value)
        return nil if value.nil?

        if multi_class
          DataStoreColumn.handle_multi_value value do |v|
            multi_class.column.type_cast v
          end
        else
          klass = self.class
          case sql_type
          when 'user' then klass.string_to_user(value)
          when 'key' then klass.string_to_key(value)
          else super
          end
        end
      end
      
      def type_cast_code(var_name)
        klass = self.class.name
        if multi_class
          ret = "#{klass}.handle_multi_value(#{var_name}) do |v| "
          ret += multi_class.column.type_cast_code "v"
          ret += " end"
          ret
        else
          case sql_type
          when 'user' then "#{klass}.string_to_user(#{var_name})"
          when 'key' then "#{klass}.string_to_key(#{var_name})"
          else super
          end
        end
      end
      
      class << self
      
        def binary_to_string value
          Blob.new(value)
        end
      
        def string_to_user(value)
          value.is_a?(User) ? value : User.new(value)
        end
    
        def string_to_key value
          begin
            value.is_a?(Key) ? value : Key.new(value)
          rescue NativeException => ex
            raise ex unless ex.cause.class == Java::JavaLang::IllegalArgumentException
          end
        end

      end
    end

    class DatastoreAdapter < AbstractAdapter
      ADAPTER_NAME = "Datastore"

      def adapter_name #:nodoc:
        ADAPTER_NAME
      end
      
      # XXX jberkman: don't know if these are all correct.
      NATIVE_DATABASE_TYPES = {
        :string => { :name => "string" },
        :text => { :name => "text" },
        :integer => { :name => "int" },
        :float => { :name => "float" },
        :decimal => { :name => "int" },
        :datetime => { :name => "datetime" },
        :timestamp => { :name => "datetime" },
        :time => { :name => "datetime" },
        :date => { :name => "datetime" },
        :binary => { :name => "blob" },
        :boolean => { :name => "bool" }
      }
      
      def native_database_types
        NATIVE_DATABASE_TYPES
      end
      
      # XXX jberkman: implement this
      def indexes(table_name, name = nil)
        []
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

      def select( sql, name = nil, binds = [] )
        log( sql.inspect, name ) {
          @connection.select_query( sql.q, sql.options )
        }
      end

      def select_rows(sql, name = nil)
        select(sql, name).map{|r| r.map{|k,v| v } }
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
        if sql.respond_to? :match
          m = sql.match /\ADELETE FROM (\w*)\z/
          sql = Arel::Visitors::Datastore::QString.new(self, m[1]) if m
        end
        log( "Delete: " + sql.inspect, name ) {
          @connection.delete_query( sql.q )
        }
      end


      def execute(sql, name = nil)
        log("Not Support: " + sql, name) {
          #@connection.execute( sql )
        } 
      end

      def create_table( table_name, options = {} )
        log( "CREATE TABLE #{table_name}", "Datastore Adapter" ) {
          td = TableDefinition.new(self)
          td.primary_key(options[:primary_key] || Base.get_primary_key(table_name.to_s.singularize)) unless options[:id] == false

          yield td if block_given?

          fields = {}
          td.columns.each do |c|
            fields[c.name.to_s] = { "default" => c.default, "type" => c.type.to_s, "null" => c.null }
            fields[c.name.to_s]["primary_key"] = true if options[:id] == false && c.name.to_s == options[:primary_key]
          end
          @connection.create_table( table_name, fields )
          td
        }
      end

      def drop_table( tname, options = {} )
        @connection.drop_table( tname )
      end

      def rename_table( tname, ntname )
        @connection.drop_table( tname, ntname )
      end

      def add_column(table_name, column_name, type, options = {})
        @connection.add_column( table_name, column_name, type, options )
      end

      alias :change_column :add_column
      
      def rename_column(table_name, column_name, new_column_name)
        @connection.rename_column table_name, column_name, new_column_name
      end
      
      def remove_column(table_name, column_name)
        @connection.remove_column(table_name, column_name)
      end

      def add_index(table_name, column_name, options = {})
        @connection.add_index( table_name, column_name, options )
      end

      def remove_index(table_name, column_name )
        @connection.remove_index( table_name, column_name )
      end

      def tables
        @connection.tables.keys
      end

      def columns( table_name, name = nil)
        @connection.columns( table_name, name ).collect{|k,opt|
          is_primary = opt["type"] == "primary_key"
          c = DataStoreColumn.new( k, opt["default"], is_primary ? "integer" : opt["type"].to_s, opt["null"] )
          c.primary = true if is_primary || opt["primary_key"]
          c
        } 
      end
      
      def primary_key( table_name )
        p_key_col = @connection.primary_key(table_name)
        column = @connection.columns(table_name).find { |k, opt| k == p_key_col }
        column ? column[0] : nil
      end

      def insert_fixture(fixture, table_name)
        o = fixture.model_class.new
        # Parse multi-param values, and don't guard as we want the key to be
        # set if present in the fixture
        o.send(:attributes=, fixture.to_hash, false)
        o.save
      end

      class DB
        def initialize( config )
          @config = { :database => 'database.yaml', :index => 'index.yaml', :namespace => 'dev' }.merge( config )
          if( @config[:database] and File.exist? @config[:database] )
            @tables = YAML.load( File.open( @config[:database], "r" ) )
          else
            @tables = {}
          end

          if( @config[:index] and File.exist? @config[:index] )
            @indexes = YAML.load( File.open( @config[:index], "r" ) )
            @indexes = @indexes[:indexes] || []
          else
            @indexes = []
          end
        end

        def create_table( tname, fields )
          @tables[tname] = fields
          save_schema
        end

        def drop_table( tname, options = {} )
          @tables.delete(tname)
          save_schema
        end

        def rename_table( tname, ntname )
          value = @tables.delete(tname)
          if( value )
            @tables[ntname] = value 
            save_schema
          end
        end

        def add_column(table_name, column_name, type, options = {})
          @tables[table_name][column_name] = { "type" => type.to_s, "default" => options[:default], "null" => options[:null] }
          save_schema
        end

        alias :change_column :add_column
        
        def remove_column(table_name, columns)
          columns = [ columns ] unless columns.respond_to? each
          columns.each do |column_name|
            @tables[table_name].delete column_name
          end
          save_schema
        end
        
        def rename_column(table_name, column_name, new_column_name)
          @tables[table_name][new_column_name] = @tables[table_name].delete column_name
          save_schema
        end

        def add_index(table_name, column_name, options = {})
          table_name  = table_name.to_s
          column_name = [ column_name ] unless column_name.is_a? Array
          column_name.map!{|c| c.to_s }
          inds = @indexes.find_all{|i| i["kind"] == table_name and i["properties"].map{|p| p["name"] } == column_name }
          if inds.empty?
            @indexes.push( { "kind" => table_name, "properties" => column_name.map{|c| { "name" => c } } } )
            save_indexes
          end
        end

        def remove_index(table_name, column_name )
          table_name  = table_name.to_s
          column_name = column_name[:column] if column_name.is_a? Hash
          column_name = [ column_name ] unless column_name.is_a? Array
          column_name.map!{|c| c.to_s }
          inds = @indexes.delete_all{|i| i["kind"] == table_name and i["properties"].map{|p| p["name"] } == column_name }
          save_indexes
        end

        def save_indexes
          f = File.open( @config[:index], 'w' )
          f.write( { "indexes" => @indexes }.to_yaml )
          f.close
        end

        def save_schema
          f = File.open( @config[:database], 'w' )
          f.write( @tables.to_yaml )
          f.close
        end
        
        def tables
          @tables
        end

        def columns( table_name, name = nil )
          tables[table_name] || {}
        end

        def primary_key( tname )
          columns(tname).each do |k, opt|
            return k if opt["type"] == "primary_key" || opt["primary_key"]
          end
          'id'
        end

        def select_query( q, options = {} )
          output = []
          if( options[:empty] )
            []
          elsif( options[:count] )
            output.push( { "count" => q.count() } )
          else
            t_name = q.kind.tableize
            p_key  = primary_key( t_name )
            column_list = columns( t_name )  
            q.fetch(options).each{|e| 
              h = {}
              column_list.each{|n,opt|
                h[n] = n == p_key ? (opt['type'] == 'key' ? e.key : e.key.id) : e[n]
              }
              output.push( h )
            }
          end
          output
        end

        def insert_query( q )
          AppEngine::Datastore.put q
          columns(q.kind.tableize).each do |n, opt|
            return q.key if opt["primary_key"] && opt["type"] == 'key'
          end
          q.key.id
        end

        def update_query( q, values = nil )
          if( values and values.size > 0 )
            entities = []
            q.each{|e|
              values.each{|k,v| e[k] = v }
              entities.push(e)
            }
            AppEngine::Datastore.put entities 
          end
        end

        def delete_query( q )
          keys = []
          q.each{|e| keys.push e.key }
          AppEngine::Datastore.delete keys
        end
      end

    end
  end
end
