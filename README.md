# ConstantRecord

ActiveRecord in-memory querying and associations for constant records and static data.
Improves performance and decreases bugs due to data mismatches.

This is compatible with all current versions of Rails, from 3.x up through 4.1
(and beyond, theoretically).

Unlike previous (ambitious) approaches that have tried to duplicate ActiveRecord
functionality in a separate set of classes, this is a simple shim that creates an
in-memory SQLite database for the relevant models.  This is designed to minimize
breakage between Rails versions.  The Rails team is famous for making sweeping
changes to the association implementation details between minor versions of Rails,
so we try to keep a Safe Distance (TM).

## Installation

Add `constant_record` to your Gemfile:

    gem 'constant_record'

Then run `bundle install`. Or, install it yourself manually, if you're into that sort of thing:

    $ gem install constant_record

*Note: The gem name is constant_record with an underscore, unlike activerecord.*

## Usage

Just `include ConstantRecord` in any ActiveRecord class. Then, you can use `data` to add
data directly in that class for clarity:

    class Genre < ActiveRecord::Base
      include ConstantRecord

      data id: 1, name: "Rock",    slug: "rock"
      data id: 2, name: "Hip-Hop", slug: "hiphop"
      data id: 3, name: "Pop",     slug: "pop"
    end

Or, you can choose to keep your data in a YAML file:

    class Genre < ActiveRecord::Base
      include ConstantRecord
      load_data File.join(Rails.root, 'config', 'data', 'genres.yml')
    end

The YAML file should be an array of hashes:

    # config/data/genres.yml
    ---
    - id: 1
      name: Rock
      slug: rock
    - id: 2
      name: Hip-Hop
      slug: hiphop
    - id: 3
      name: Pop
      slug: hop

You can omit the filename if it follows the naming convention of `config/data/[table_name].yml`:

    class Genre < ActiveRecord::Base
      include ConstantRecord
      load_data  # config/data/genres.yml
    end

Alternatively, you can load your data via some other external method.  Note that you will need
to reload your data each time Rails restarts, since the data is in-memory only.  This means
adding a reload hook after Unicorn / Passenger / Puma fork:

    Genre.reload!

Once you define your class, this will create an in-memory `sqlite` database which is then
hooked into ActiveRecord.  A database table is created on the fly, consisting of the columns
you use in the *first* `data` declaration.  **Important:** This means if you have a couple
columns that aren't always present, *make sure to include them with `column_name: nil` on
the first `data` line:*

    class Genre < ActiveRecord::Base
      include ConstantRecord

      data id: 1, name: "Rock",    slug: "rock",   region: nil, country: nil
      data id: 2, name: "Hip-Hop", slug: "hiphop", region: 'North America'
      data id: 3, name: "Pop",     slug: "pop",    country: 'US'
    end

Once setup, all the familiar ActiveRecord finders work:

    Genre.find(1)
    Genre.find_by_slug("pop")
    Genre.where(name: "Rock").first

And so on.  Attempts to modify values will fail:

    @genre = Genre.find(2)
    @genre.slug = "hip-hop"
    @genre.save!  # nope

You'll get an `ActiveRecord::ReadOnlyRecord` exception.

## Auto Constants

ConstantRecord will also create constants on the fly for you if you have a `name` column.
Revisiting our example:

    class Genre < ActiveRecord::Base
      include ConstantRecord

      data id: 1, name: "Rock",    slug: "rock"
      data id: 2, name: "Hip-Hop", slug: "hiphop"
      data id: 3, name: "Pop",     slug: "pop"
    end

This will create:

    Genre::ROCK = 1
    Genre::HIP_HOP = 2
    Genre::POP = 3

This makes it cleaner to do queries in your app:

    Genre.find(Genre::ROCK)
    Song.where(genre_id: Genre::ROCK)

And such things.

## Associations

Internally, ActiveRecord tries to do joins to retrieve associations.  This doesn't work, since
the records live in different tables.  Have no fear, you just need to `include ConstantRecord::Associations`
in the normal ActiveRecord class that is trying to associate to your ConstantRecord class:

    class Genre < ActiveRecord::Base
      include ConstantRecord

      has_many :song_genres
      has_many :songs, through: :song_genres

      data id: 1, name: "Rock",    slug: "rock",   region: nil, country: nil
      data id: 2, name: "Hip-Hop", slug: "hiphop", region: 'North America'
      data id: 3, name: "Pop",     slug: "pop",    country: 'US'
    end

    class SongGenre < ActiveRecord::Base
      belongs_to :genre_id
      belongs_to :song_id
    end

    class Song < ActiveRecord::Base
      include ConstantRecord::Associations
      has_many :song_genres
      has_many :songs, through: :song_genres
    end

If you forget to do this, you'll get an error like this:

    irb(main):001:0> @song = Song.first
    irb(main):002:0> @song.genres
    ActiveRecord::StatementInvalid: Could not find table 'song_genres'

It would be great to remove this shim, but I can't currently see a way without monkey-patching
the internals of ActiveRecord, which I don't want to do for 17 different reasons.

## Debugging

If you forget to define data, you'll get a "table doesn't exist" error:

    class Publisher < ActiveRecord::Base
      include ConstantRecord

      # Oops no data

      has_many :article_publishers
      has_many :articles, through: :article_publishers
    end

    irb(main):001:0> @publisher = Publisher.first
    irb(main):002:0> @publisher.articles
    ActiveRecord::StatementInvalid: Could not find table 'articles'

This is because the table is created lazily when you first load data.

## Other Projects

Inspired by a couple previous efforts:

* Christoph Petschnig's [constantrecord](https://github.com/cpetschnig/constantrecord)
* Aaron Quint's [static_model](https://github.com/quirkey/static_model)
* Nico Taing's [yaml_record](https://github.com/nicotaing/yaml_record)

Other projects seen in the wild:

* [static_record](https://github.com/dejan/static_record)
* [constant_record](https://github.com/topdan/constant_record)
* [frozen_record](https://github.com/byroot/frozen_record)

All are good efforts, but unfortunately ActiveRecord continues to make sharp left turns
with its internals.  This makes it very difficult to maintain compatibility over time
if you write a gem that is too tightly coupled to Rails.
