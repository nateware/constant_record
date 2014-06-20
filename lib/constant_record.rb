#
# Inherit from `ConstantRecord::Base` just like you would with ActiveRecord.
# Then, you can use `data` to add data directly in that class for clarity:
#
#     class Genre < ConstantRecord::Base
#       data id: 1, name: "Rock",    slug: "rock"
#       data id: 2, name: "Hip-Hop", slug: "hiphop"
#       data id: 3, name: "Pop",     slug: "pop"
#     end
#
# Or, you can choose to keep your data in a YAML file:
#
#     class Genre < ConstantRecord::Base
#       load_data File.join(Rails.root, 'config', 'data', 'genres.yml')
#     end
#
# The YAML file should be an array of hashes.  Once initialized, all
# familiar ActiveRecord finders and associations should work as expected.
#
require "active_record"
require "constant_record/version"

module ConstantRecord
  class Error < StandardError; end
  class BadDataFile < Error;   end

  DATABASE_CONFIG = { adapter: 'sqlite3', database: ":memory:", pool: 5 }.freeze

  class << self
    def data_dir
      @data_dir || File.join('config', 'data')
    end

    def data_dir=(path)
      @data_dir = path
    end
  end

  #
  # Loads data either directly in the model class, or from a YAML file.
  #
  module DataLoading
    def data_file
      @data_file || File.join(ConstantRecord.data_dir, "#{self.to_s.tableize}.yml")
    end

    def load_data(file=nil)
      @data_file = file
      reload!
    end

    def load(reload=false)
      return if loaded? && !reload
      records = YAML.load_file(data_file)

      if !records.is_a?(Array) or records.empty?
        raise BadDataFile, "Expected array in data file #{data_file}: #{records.inspect}"
      end

      # Call our method to populate data
      @data_rows = []
      records.each{|r| data r}

      @loaded = true
    end

    def reload!
      load(true)
    end

    def loaded?
      @loaded || false
    end

    # Define a constant record: data id: 1, name: "California", slug: "CA"
    def data(attrib, reload=false)
      raise ArgumentError, "#{self}.data expects a Hash of attributes" unless attrib.is_a?(Hash)
      attrib.symbolize_keys!

      unless attrib[primary_key.to_sym]
        raise ArgumentError, "#{self}.data missing primary key '#{primary_key}': #{attrib.inspect}"
      end

      # Save data definitions for reload on connection change
      @data_rows ||= []

      # Check for duplicates
      unless reload
        if old_record = @data_rows.detect{|r| r[primary_key.to_sym] == attrib[primary_key.to_sym] }
          raise ActiveRecord::RecordNotUnique,
            "Duplicate #{self} id=#{attrib[primary_key.to_sym]} found: #{attrib} vs #{old_record}"
        end
        @data_rows << attrib
      end

      # Create table dynamically based on first row of data
      create_memory_table(attrib) unless connection.table_exists?(table_name)

      # Save to in-memory table
      new_record = new(attrib)
      new_record.id = attrib[primary_key.to_sym]
      new_record.save!

      # Create Ruby constants as well, so "id: 3, name: Sky" generates SKY=3
      if new_record.respond_to?(:name) and name = new_record.name
        const_name =
          name.to_s.upcase.strip.gsub(/[-\s]+/,'_').sub(/^[0-9_]+/,'').gsub(/\W+/,'')
        const_set const_name, new_record.id unless const_defined?(const_name)
      end
    end

    protected

    # Create our in-memory table based on columns we have defined in our data.
    def create_memory_table(attrib)
      db_columns = {}
      attrib.each do |col,val|
        next if col.to_s == 'id' # skip pk
        db_columns[col] =
          case val
          when Integer then :integer
          when Float   then :decimal
          when Date    then :date
          when DateTime, Time then :datetime
          else :string
          end
      end

      # Create the table in memory
      connection.create_table(table_name) do |t|
        db_columns.each do |col,type|
          t.column col, type
        end
      end
    end

    # Reloads the table when the connection has changed
    def reload_memory_table
      return false unless @data_rows
      @data_rows.each{|r| data r, true}
    end
  end

  #
  # Hooks to integrate ActiveRecord associations with constant records.
  #
  module Associations
    def self.included(base)
      base.extend self # support "include"
    end

    #
    # Override the default ActiveRecord.has_many(:through) that does in-database joins,
    # with a method that makes two fetches.  It's the only reliable way to traverse
    # databases. Hopefully one (or both) of these tables are in-memory ConstantRecords
    # so that we're not making real DB calls.
    #
    def has_many(other_table, options={})
      super other_table, options.dup # make AR happy

      # Redefine association method in the class
      if join_tab = options[:through]
        foreign_key = options[:foreign_key] || other_table.to_s.singularize.foreign_key
        prime_key   = options[:primary_key] || primary_key
        class_name  = options[:class_name]  || other_table.to_s.classify
        join_key    = table_name.to_s.singularize.foreign_key

        define_method other_table do
          join_class = join_tab.to_s.classify.constantize
          ids = join_class.where(join_key => send(prime_key)).pluck(foreign_key)
          return [] if ids.empty?
          class_name.constantize.where(id: ids)
        end
      end
    end
  end

  #
  # Raise an error if the application attempts to change constant records.
  #
  module ReadOnly
    def self.included(base)
      base.extend ClassMethods
    end

    def readonly?
      # have to allow inserts to load_data
      new_record? ? false : true
    end

    def delete
      raise ActiveRecord::ReadOnlyRecord
    end

    def destroy
      raise ActiveRecord::ReadOnlyRecord
    end

    module ClassMethods
      def delete(id_or_array)
        raise ActiveRecord::ReadOnlyRecord
      end

      def delete_all(conditions = nil)
        raise ActiveRecord::ReadOnlyRecord
      end

      def update_all(conditions = nil)
        raise ActiveRecord::ReadOnlyRecord
      end
    end
  end

  #
  # Base class to inherit from so we can share the same memory database
  #
  class Base < ActiveRecord::Base
    extend  DataLoading
    extend  Associations
    include ReadOnly

    # Reload table if connection changes. Since it's in-memory, a connection
    # change means the the table gets wiped.
    def self.connection
      conn = super
      if (@previous_connection ||= conn) != conn
        @previous_connection = conn # avoid infinite loop
        reload_memory_table
      end
      conn
    end

    self.abstract_class = true
    establish_connection ConstantRecord::DATABASE_CONFIG
  end
end
