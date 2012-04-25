# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name        = "activerecord-datastore-adapter"
  s.version     = "0.0.4"
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Mohammed Siddick"]
  s.email       = ["siddick@gmail.com"]
  s.homepage    = "https://github.com/siddick/datastore"
  s.summary     = %q{ActiveRecord Adapter for Appengine Datastore}
  s.description = %q{Just an ActiveRecord Adapter for the Appengine Datastore. 
    Create Rails3 application: rails new app_name -m http://siddick.github.com/datastore/rails3.rb}

  s.rubyforge_project = "activerecord-datastore-adapter"

  s.files = %w{
.gitignore
Gemfile
Gemfile.lock
MIT-LICENSE
README.textile
Rakefile
activerecord-datastore-adapter.gemspec
examples/rails3.rb
examples/rails3_edge.rb
lib/active_record/connection_adapters/datastore_adapter.rb
lib/active_record/datastore_associations_patch.rb
lib/arel/visitors/datastore.rb
spec/create_table_spec.rb
spec/datatypes_spec.rb
spec/operators_spec.rb
spec/query_spec.rb
spec/relations_spec.rb
spec/spec_helper.rb
spec/table_schema.rb
      }

  s.files.each do |f|
    s.test_files << f if f =~ /(test|spec|features)\/.*/
    s.executables << f if f =~ /(bin)\/.*/
  end
  s.require_paths = ["lib"]

  s.add_dependency( 'appengine-apis', '>= 0.0.22' )
  s.add_dependency( 'activerecord', '~> 3.0.6' )
  s.add_dependency( 'arel', '>= 2.0.7' )
end
