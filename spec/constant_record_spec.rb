require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "ConstantRecord" do
  describe "loading data" do
    it "data(attr: val)" do
      date1 = Time.now
      date2 = Date.new
      date3 = DateTime.new

      # insert out of order to ensure we can override ID
      Author.data(id: 1, name: "One",   birthday: date1)
      Author.data(id: 3, name: "Three", birthday: date3)
      Author.data(id: 2, name: "Two",   birthday: date2)

      Author.count.should == 3
      Author.find(1).name.should == "One"
      Author.find(2).name.should == "Two"
      Author.find(3).name.should == "Three"

      author = Author.find_by_name("One")
      author.id.should == 1
      author.birthday.should == date1

      author = Author.find_by_name("Two")
      author.id.should == 2
      author.birthday.should == date2

      author = Author.find_by_name("Three")
      author.id.should == 3
      author.birthday.should == date3
    end

    it "supports AR finders" do
      Author.where(id: [1,2]).count.should == 2
      Author.where(['name like ?', 'Three']).count.should == 1
      Author.where(['birthday <= ?', Time.now]).count.should == 3
    end

    it "rejects dup ID's" do
      should.raise(ActiveRecord::RecordNotUnique){ Author.data(id: 3, name: "Three") }
    end

    it "loads a YAML file path/to/my.yml" do
      Publisher.load_data
      Publisher.count.should == 3
      Publisher.find(2).name == 'Penguin'
    end

    it "supports reload!" do
      Publisher.where('id is not null').delete_all # hackaround ReadOnlyRecord
      Publisher.count.should == 0
      Publisher.reload!
      Publisher.count.should == 3
      Publisher.data(id: 23, name: "Flop")
      Publisher.count.should == 4
    end

    it "rejects missing data files" do
      should.raise(Errno::ENOENT){ Publisher.load_data 'nope.yml' }
    end

    it "rejects empty data files" do
      should.raise(ConstantRecord::BadDataFile){ Publisher.load_data 'spec/data/empty.yml' }
    end
  end

  describe "creates constants" do
    it "simple values" do
      Publisher.data(id: 3, name: "Simple Value")
      Publisher::SIMPLE_VALUE.should == 3
    end
    it "complex strings" do
      Publisher.data(id: 4, name: " 2 Non-Fiction, Bestsellers! ")
      Publisher::NON_FICTION_BESTSELLERS.should == 4
    end
  end

  describe "associations" do
    it "belongs_to" do
      Article.create!(author_id: 1)
      Article.create!(author_id: 2)
      Article.create!(author_id: 3)
      Article.create!(author_id: 2)
      Article.create!(author_id: 1)
      author  = Author.find(1)
      article = Article.find(5)
      article.author.id.should == author.id
    end

    it "has_many" do
      author = Author.find(2)
      author.articles.count.should == 2
      author.articles.find(4).id.should == 4
    end

    it "has_many through (up)" do
      ArticlePublisher.create!(article_id: 4,  publisher_id: 7)
      ArticlePublisher.create!(article_id: 5,  publisher_id: 7)
      ArticlePublisher.create!(article_id: 60, publisher_id: 7) # bogus
      publisher = Publisher.find(7)
      publisher.name.should == "Marvel"
      publisher.article_publishers.count.should == 3
      publisher.articles.count.should == 2
      publisher.articles.each do |art|
        art.should == Article.find(art.id)
      end
    end

    it "has_many through (down)" do
      ArticlePublisher.create!(article_id: 2, publisher_id: 1)
      ArticlePublisher.create!(article_id: 2, publisher_id: 2)
      ArticlePublisher.create!(article_id: 2, publisher_id: 30) # bogus
      article = Article.find(2)
      article.article_publishers.count.should == 3
      article.publishers.count.should == 2
    end
  end

  describe "readonly records" do
    before do
      @publisher = Publisher.find(1)
    end

    it "readonly? == true" do
      @publisher.readonly?.should.be.true?
    end

    it "rejects destroy" do
      should.raise(ActiveRecord::ReadOnlyRecord){ @publisher.destroy }
    end

    it "rejects delete" do
      should.raise(ActiveRecord::ReadOnlyRecord){ @publisher.delete }
    end

    it "rejects update_all" do
      should.raise(ActiveRecord::ReadOnlyRecord){ Publisher.update_all('id = null') }
    end

    # it "rejects update_all thru associations" do
    #   should.raise(ActiveRecord::ReadOnlyRecord){ Publisher.where(id: 1).update_all('id = null') }
    # end

    it "rejects delete_all" do
      should.raise(ActiveRecord::ReadOnlyRecord){ Publisher.delete_all }
    end

    # it "rejects delete_all thru associations" do
    #   should.raise(ActiveRecord::ReadOnlyRecord){ Publisher.where(id: 1).delete_all }
    # end

    it "rejects destroy_all" do
      should.raise(ActiveRecord::ReadOnlyRecord){ Publisher.destroy_all }
    end

    # it "rejects destroy_all thru associations" do
    #   should.raise(ActiveRecord::ReadOnlyRecord){ Publisher.where(id: 1).destroy_all }
    # end
  end
end

