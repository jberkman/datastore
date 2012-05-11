require 'arel'
require 'arel/visitors'
require 'arel/visitors/to_sql'
require 'appengine-apis/datastore'

module Arel
  module Visitors
    class Datastore < Arel::Visitors::ToSql

      class QString
        JavaKey = Java::ComGoogleAppengineApiDatastore::Key

        attr :kind
        attr :q 
        attr :options
        attr :connection

        def initialize( conn, kind, options = {} )
          @connection = conn
          @kind = kind
          @q = AppEngine::Datastore::Query.new( kind )
          @options = options
        end

        def to_s
          out = q.inspect 
          out += " OFFSET #{options[:offset]} " if options[:offset]  
          out += " LIMIT  #{options[:limit]} "  if options[:limit]  
          out
        end

        alias :inspect :to_s

        def projections( projs )
          projs.each{|p|
            if( p.is_a? Arel::Nodes::Count )
              options[:count] = true
            end
          }
          self
        end

        def wheres( conditions )
          conditions.each{|w|
            w_expr  = w.expr rescue w
            if( w_expr.class != Arel::Nodes::SqlLiteral )
              key     = w_expr.left.name
              val     = w_expr.right
              opt     = w_expr.operator
              apply_filter( key, opt, val )
            else
              parese_expression_string( w_expr.to_s )
            end
          }
          self
        end

        TypeCast = {
          :primary_key => lambda { |k,v|
            return v if v.is_a? AppEngine::Datastore::Key
            v = v.to_i if v.respond_to?(:match) && v.match(/\A\d+\z/)
            if v.is_a? String
              begin
                return AppEngine::Datastore::Key.new v
              rescue NativeException => e
              end
            end
            AppEngine::Datastore::Key.from_path k, v
          },
          :integer     => lambda{|k,i| i.to_i },
          :datetime    => lambda{|k,t| t.is_a?(Time)? t : Time.parse(t.to_s) },
          :date        => lambda{|k,t| t.is_a?(Date)? t : Date.parse(t.to_s) },
          :float       => lambda{|k,f| f.to_f },
          :text        => lambda{|k,t| AppEngine::Datastore::Text.new(t) },
          :binary      => lambda{|k,t| AppEngine::Datastore::Blob.new(t) },
          :boolean     => lambda{|k,b| b == true || b.to_s =~ (/(true|t|yes|y|1)$/i) ? true : false }
        }
        InScan = /'((\\.|[^'])*)'|(\d+)/
        def apply_filter( key, opt, value )
          key, opt = key.to_sym, opt.to_sym
          column = @connection.columns(kind.tableize).find{|c| c.name == key.to_s }
          opt = :in      if value.is_a? Array
          type_cast_proc = TypeCast[ (column.nil? && key == :ancestor) || column.primary ? :primary_key : column.type ]
          if opt == :in or opt == :IN
            value = value.scan(InScan).collect{|d| d.find{|i| i}}   if value.is_a? String
            value.collect!{|v| type_cast_proc.call(kind,v) }        if type_cast_proc
            options[:empty], value = true, [ "EMPTY" ]              if value.empty?
          else
            value = type_cast_proc.call( kind, value ) if type_cast_proc
          end
          if column.nil? && key == :ancestor && opt == :==
            q.ancestor = value
          else
            key = :__key__ if column.primary
            q.filter( key, opt, value )
          end
        end

        
        RExpr = Regexp.union( /(in)/i,
                     /\(\s*(('((\\.|[^'])*)'|\d+)(\s*,\s*('((\\.|[^'])*)'|\d+))*)\s*\)/,
                     /"((\\.|[^"])*)"/,
                     /'((\\.|[^'])*)'/,
                     /([\w\.]+)/,
                     /([^\w\s\.'"]+)/ )
        Optr      = { "=" => :== }
        ExOptr    = ["(",")"]
        def parese_expression_string( query )
          datas = query.scan( RExpr ).collect{|a| a.find{|i| i } }
          datas.delete_if{|d| ExOptr.include?(d) }
          while( datas.size >= 3 )
            key = datas.shift.sub(/^[^.]*\./,'').to_sym
            opt = datas.shift
            val = datas.shift
            concat_opt = datas.shift
            apply_filter( key, Optr[opt] || opt.to_sym, val )
          end
        end

        def orders( ords )
          ords.each do |o|
            if( o.is_a? String )
              o.split(',').each do |pair|
                key, dir, notuse = pair.split
                dir = case dir
                when /ASC/i
                  AppEngine::Datastore::Query::ASCENDING
                when /DESC/i
                  AppEngine::Datastore::Query::DESCENDING
                end
                q.sort( key, dir )
              end
            else
              q.sort(o.expr, o.direction)
            end
          end
          self
        end
      end

      def get_limit_and_offset( o )
        options = {}
        options[:limit]  = o.limit.expr if o.limit
        options[:offset] = o.offset.expr if o.offset
        options
      end

      def visit_Arel_Nodes_SelectStatement o
        c    = o.cores.first
        QString.new( @connection, c.froms.name.classify, get_limit_and_offset(o) ).wheres( c.wheres ).orders(o.orders).projections( c.projections )
      end

      def insert_type_case( value )
        value.is_a?( ActiveSupport::TimeWithZone ) ? value.time : value
      end

      def visit_Arel_Nodes_InsertStatement o
        e = AppEngine::Datastore::Entity.new(o.relation.name.classify)
        o.columns.each_with_index{|c,i| e[c.name] = insert_type_case(o.values.left[i]) }
        e
      end

      def visit_Arel_Nodes_UpdateStatement o
        QString.new( @connection, o.relation.name.classify, :values => o.values.collect{|v| [ v.left.name, insert_type_case(v.right) ] } ).wheres( o.wheres )
      end

      def visit_Arel_Nodes_DeleteStatement o
        QString.new( @connection, o.relation.name.classify ).wheres( o.wheres )
      end

    end
  end
end

Arel::Visitors::VISITORS['datastore'] = Arel::Visitors::Datastore
