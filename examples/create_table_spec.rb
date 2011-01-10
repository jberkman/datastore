
$LOAD_PATH.push( File.join( File.dirname( __FILE__ ), '..', 'lib' ) )
require 'active_record'
require 'logger'


ActiveRecord::Base.logger = Logger.new( STDERR )

class Person < ActiveRecord::Base
  establish_connection :adapter => 'dstore', :database => 'database.yml', :index => 'indexs.yml'

  connection.create_table table_name, :force => true do |t|
    t.string :name
    t.string :description
  end
end

p =  Person.find_by_name_and_description("gold", "nothing")
puts p.inspect

if p 
  p.name = "happy"
  p.save
end

#puts Person.where( :id => [ 16, 14 ] ).inspect
# bob = Person.create!(:name => 'gold', :description => "nothing")
#puts Person.inspect
#puts Person.all.inspect
#bob.destroy
#puts Person.all.inspect

