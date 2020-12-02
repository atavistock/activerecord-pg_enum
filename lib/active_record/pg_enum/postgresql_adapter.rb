module ActiveRecord
  module PGEnum
    register :postgresql_adapter do
      require "active_record/connection_adapters/postgresql_adapter"
      ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.include PostgreSQLAdapter
      ActiveRecord::ConnectionAdapters::PostgreSQLAdapter::NATIVE_DATABASE_TYPES.merge!(enum: { name: "enum" })
    end

    module PostgreSQLAdapter
      # Helper method used by the monkeypatch internals. Provides a hash of ENUM types as they exist currently.
      #
      # Example:
      #
      #   { "foo_type" => ["foo", "bar", "baz"] }
      def enum_types
        pg_type = Arel::Table.new(:pg_type)
        pg_enum = Arel::Table.new(:pg_enum)
        pg_namespace = Arel::Table.new(:pg_namespace)
        current_schema = Arel::Nodes::NamedFunction.new('current_schemas', [Arel::Nodes::False.new])
        any_current_schema = Arel::Nodes::NamedFunction.new('ANY', [current_schema])

        query = pg_type.
          project(pg_type[:typname], pg_enum[:enumlabel]).
          join(pg_enum).on(pg_enum[:enumtypid].eq(pg_type[:oid])).
          join(pg_namespace).on(pg_type[:typnamespace].eq(pg_namespace[:oid])).
          where(pg_namespace[:nspname].eq(any_current_schema)).
          order(pg_type[:typname], pg_enum[:enumsortorder])
        rows = ActiveRecord::Base.connection.select_rows(query.to_sql)

        rows.reduce({}) do |accum, (type, value)|
          accum[type.to_s] ||= []
          accum[type.to_s] << value.to_s
          accum
        end
      end

      # Helper method that returns only the values of a specific ENUM types.  Uses a WeakRef as a short lived
      # cache to prevent hitting the database for every enum on startup.
      #
      # Returns an array of strings like ["foo", "bar", "baz"]
      def enum_values(type_name)
        @_cached_enum_types ||= WeakRef.new(enum_types)
        @_cached_enum_types[type_name.to_s]
      end

      # Helper method to creates an ActiveRecord enum, inferring the values from the ENUM type specified.
      #
      # Can be called as `postgres_enum(:foo, :foo_type)`
      #
      def postgres_enum(name, type_name = nil)
        type_name ||= name
        values = enum_values(type_name)
        enum name.to_sym => values.zip(values)
      end
    end

  end
end
