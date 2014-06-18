# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'constant_record/version'

Gem::Specification.new do |spec|
  spec.name          = "constant_record"
  spec.version       = ConstantRecord::VERSION
  spec.authors       = ["Nate Wiger"]
  spec.email         = ["nwiger@gmail.com"]
  spec.summary       = %q{In-memory ActiveRecord querying and associations for static data.}
  spec.description   = <<-EndDesc
  In-memory ActiveRecord querying and associations for static data.
  Improves performance and decreases bugs due to data mismatches.
  EndDesc
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  # Allow any AR versions, but need at least one. Also sqlite for the table.
  spec.add_dependency "activerecord"
  spec.add_dependency "sqlite3"

  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "bacon"
end
