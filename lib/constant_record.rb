#
# To use, `include ConstantRecord` in any ActiveRecord class. Then, you can use `data`
# to add data directly in that class for clarity:
#
#     class Genre < ActiveRecord::Base
#       include ConstantRecord
#
#       data id: 1, name: "Rock",    slug: "rock"
#       data id: 2, name: "Hip-Hop", slug: "hiphop"
#       data id: 3, name: "Pop",     slug: "pop"
#     end
#
# Or, you can choose to keep your data in a YAML file:
#
#     class Genre < ActiveRecord::Base
#       include ConstantRecord
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

  MEMORY_DBCONFIG = {adapter: 'sqlite3', database: ":memory:", pool: 5}.freeze


  class << self
    def memory_dbconfig
      @memory_dbconfig || MEMORY_DBCONFIG
    end

    def memory_dbconfig=(config)
      @memory_dbconfig = config
    end

    def data_dir
      @data_dir || File.join('config', 'data')
    end

    def data_dir=(path)
      @data_dir = path
    end

    def included(base)
      base.extend DataLoading
      base.extend Associations
      base.send :include, ReadOnly
      base.establish_connection(memory_dbconfig) unless base.send :connected?
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
    def data(attrib)
      attrib.symbolize_keys!
      raise ArgumentError, "#{self}.data expects a Hash of attributes" unless attrib.is_a?(Hash)

      unless attrib[primary_key.to_sym]
        raise ArgumentError, "#{self}.data missing primary key '#{primary_key}': #{attrib.inspect}"
      end

      unless @table_was_created
        create_memory_table(attrib)
        @table_was_created = true
      end

      new_record = new(attrib)
      new_record.id = attrib[primary_key.to_sym]

      # Check for duplicates
      if old_record = find_by_id(new_record.id)
        raise ActiveRecord::RecordNotUnique,
          "Duplicate #{self} id=#{new_record.id} found: #{new_record} vs #{old_record}"
      end
      new_record.save!

      # create Ruby constants as well, so "id: 3, name: Sky" gets SKY=3
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
  end

  #
  # Hooks to integrate ActiveRecord associations with constant records.
  #
  module Associations
    def self.included(base)
      base.extend self # support "include" as well
    end

    #
    # Override the default ActiveRecord.has_many(:through) that does in-database joins,
    # with a method that makes two fetches.  It's the only reliable way to traverse
    # databases. Hopefully one (or both) of these tables are in-memory ConstantRecords
    # so that we're not making real DB calls.
    #
    def has_many(other_table, options={})
      # puts "#{self}(#{table_name}).has_many #{other_table.inspect}, #{options.inspect}"
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
      else
        super other_table, options
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
end
