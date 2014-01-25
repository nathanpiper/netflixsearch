require 'rubygems'
require 'bundler/setup'

require 'open-uri'
require 'nokogiri'
require 'net/http'
require 'thor'
require 'sqlite3'
require 'active_record'

# Configuration
COUNTRIES = {
	'usa' => 'http://netflixusacompletelist.blogspot.com/',
	'canada' => 'http://netflixcanadacompletelist.blogspot.com/',
	'uk' => 'http://netflixukcompletelist.blogspot.com/',
	'ireland' => 'http://netflixirelandcompletelist.blogspot.com/',
	'brazil' => 'http://netflixbrazilcompletelist.blogspot.com/',
	'mexico' => 'http://netflixmexicocompletelist.blogspot.com/',
	'norway' => 'http://netflixnorwaycompletelist.blogspot.com/',
	'sweden' => 'http://netflixswedencompletelist.blogspot.com/',
	'netherlands' => 'http://netflixnetherlandscompletelist.blogspot.com/',
	'denmark' => 'http://netflixdenmarkcompletelist.blogspot.com/',
	'finland' => 'http://netflixfinlandcompletelist.blogspot.com/'
}

# Database schema
SCHEMA_SQL = <<-eos
	CREATE TABLE titles (id integer primary key, name varchar(255), years varchar(16));
	CREATE TABLE title_countries (title_id integer, country_id integer, primary key(title_id, country_id));
	CREATE TABLE countries (id integer primary key, name varchar(64));
	CREATE INDEX titles_name on titles(name);
	CREATE INDEX countries_name on countries(name);
	CREATE INDEX title_countries_title_id on title_countries(title_id);
	CREATE INDEX title_countries_country_id on title_countries(country_id);
eos

DB_EXISTS = File.exists?('titles.db')

# ActiveRecord setup
ActiveRecord::Base.establish_connection(
  :adapter => 'sqlite3',
  :database => 'titles.db'
)

# Create the schema if it doesn't exist
if not DB_EXISTS then
	puts 'creating db ...'
	SCHEMA_SQL.split("\n").each{|s| ActiveRecord::Base.connection.execute(s)}
end

class TitleCountry < ActiveRecord::Base
  belongs_to :title
  belongs_to :country
end

class Title < ActiveRecord::Base
	has_many :title_countries
	has_many :countries, through: :title_countries
	
	def available_in_country?(country_name)
		self.countries.where(id: Country.find_by(name: country_name).id).exists?
	end
end

class Country < ActiveRecord::Base
	has_many :title_countries
	has_many :titles, through: :title_countries
end

class NetflixSearch < Thor
	package_name 'Netflix Search'

	no_commands do
		def find_links_in_page(page_url, selector='a[href]')
			doc = Nokogiri::HTML(open(page_url))
			doc.css(selector)
		end
		
		def populate_country_titles(country_name, url)
			puts "retrieving #{country_name} ..."
			
			# Find the latest month index page url
			latest_month_url = find_links_in_page(url).map{|l| l['href']}.find{|l| l.include?('archive') and l.include?(Time.now.year.to_s)}

			# Find the latest alphabetical listing url
			latest_alphabetical_url = find_links_in_page(latest_month_url).map{|l| l['href']}.find{|l| l.include?('alphabetical')}

			# Extract titles
			ActiveRecord::Base.transaction do
				find_links_in_page(latest_alphabetical_url, 'b a[href]').each do |l|
					# Update the database
					title = Title.find_or_create_by(name: l.text)
					country = Country.find_or_create_by(name: country_name) 
		
					title.countries << country unless title.available_in_country?(country_name)
				end
			end
		end
	end

	desc "updatedb", "Updates the database with a list of the titles available on all known Netflix regions"
	def updatedb()
		# Retrieve the latest titles
		COUNTRIES.each do |country, url|
			populate_country_titles(country, url)
		end
	end

	desc "search [TERM]", "lists matching titles and shows countries that have the title"
	def search(term)
		updatedb() unless DB_EXISTS
		puts "searching for '#{term}' ..."
		Title.where('name like ?', "%#{term}%").each do |t|
			puts "\t#{t.name}"
			t.countries.map(&:name).each{|c| puts "\t\t#{c}"}
		end
	end
end
