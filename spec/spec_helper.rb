$LOAD_PATH.unshift File.expand_path(File.dirname(__FILE__) + '/../lib')
require 'bacon'
Bacon.summary_at_exit
if $0 =~ /\brspec$/
  raise "\n===\nThese tests are in bacon, not rspec.  Try: bacon #{ARGV * ' '}\n===\n"
end

require 'date' # datetime
require 'constant_record'
require 'active_record'
require 'sqlite3'

# Override path for testing purposes
TEST_YAML_DATA_DIR = File.join(File.dirname(__FILE__), 'data')
ConstantRecord.data_dir = TEST_YAML_DATA_DIR

# Our "persistent" sqlite database for "real" records (not in-memory)
TEST_SQLITE_DB_FILE = File.join(File.dirname(__FILE__), 'test.sqlite3')
File.unlink TEST_SQLITE_DB_FILE rescue nil
at_exit do
  File.unlink TEST_SQLITE_DB_FILE rescue nil
end

ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: TEST_SQLITE_DB_FILE,
  pool: 5
)

if ENV['DEBUG']
  ActiveRecord::Base.logger = Logger.new(STDOUT)
  ActiveRecord::Base.logger.level = Logger::DEBUG
end

class Author < ActiveRecord::Base
  include ConstantRecord

  has_many :articles
end

class Publisher < ActiveRecord::Base
  include ConstantRecord

  has_many :article_publishers
  has_many :articles, through: :article_publishers
end

class Article < ActiveRecord::Base
  include ConstantRecord::Associations
  belongs_to :author
  has_many :article_publishers
  has_many :publishers, through: :article_publishers
end


class ArticlePublisher < ActiveRecord::Base
  belongs_to :article
  belongs_to :publisher
end

# Setup ActiveRecord tables
Article.connection.create_table(:articles) do |t|
  t.string  :title
  t.integer :author_id
end

ArticlePublisher.connection.create_table(:article_publishers) do |t|
  t.string  :article_id
  t.integer :publisher_id
end
