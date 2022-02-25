# encoding: UTF-8
DB_FILE_PATH = ENV.fetch('DB_FILE_PATH', "./modern_solutions.sqlitedb")
begin
  require "bundler/inline"
rescue LoadError => e
  $stderr.puts "Bundler version 1.10 or later is required. Please update your Bundler"
  raise e
end
  
gemfile(true) do
  source "https://rubygems.org"

  gem "rails"
  gem "sqlite3"
  gem "hairtrigger"
  gem 'pry'
  # gem "stateful_controller"
end

require "active_record"
# require "action_controller/railtie"
# require 'active_record/connection_adapters/sqlite3_adapter'

# class ActiveRecord::ConnectionAdapters::SQLite3Adapter
#   def initialize(db, logger, config)
#   end
# end
  #   def initialize(db, logger, config=nil)
#     super

#     db.create_function('hmac', 2) do |func, key, data|
#       mac = OpenSSL::HMAC.hexdigest("SHA256", key, data.to_json)
#       func.result = mac
#     end
#   end
# end
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: DB_FILE_PATH)
ActiveRecord::Base.logger = Logger.new(STDOUT)

# Everyone is somebody else's kid.
# The difference is in these three primary cases.
#
# 1) A parent will have no parent : but will have kids
# 2) A carer may have some parents: and may have some kids
# 3) A kid will have parents      : but have no kids
#
# There is a rule that a carer with no kids will have no parents. i.e., Orphaned

# Data:
# This data comes from the exercise
#
# ┌─────┬──────────┬───────────────┬───────────┬──────────┬──────────────┬───────────────┬──────────┐
# │ id  │ PersonId │     Name      │ AccountId │ isPickup │    KidIds    │ Type(Derived) │   DOB    │
# ├─────┼──────────┼───────────────┼───────────┼──────────┼──────────────┼───────────────┼──────────┤
# │  10 │      201 │ Patrick Smith │ NULL      │ true     │ "23, 12, 10" │ Carer         │ NULL     │
# │  11 │      202 │ Michael Doe   │ NULL      │ false    │ "23, 12, 5"  │ Carer         │ NULL     │
# │ 101 │       23 │ James Smith   │ 1         │ NULL     │ NULL         │ Kid           │ 12/10/19 │
# │ 102 │       12 │ Jane Smith    │ 1         │ NULL     │ NULL         │ Kid           │ 12/11/19 │
# │ 103 │       15 │ John Doe      │ 2         │ NULL     │ NULL         │ Kid           │ 12/12/19 │
# │ 104 │       19 │ Jerome Smith  │ 1         │ NULL     │ NULL         │ Kid           │ 12/13/19 │
# └─────┴──────────┴───────────────┴───────────┴──────────┴──────────────┴───────────────┴──────────┘
#  
# Caveats
# 1) A carer with no kids will also have no parents as a rule. i.e., "Orphan"
# 2) A carer may be a parent, but is expected to have another account.
# 3) A carer may not be working currently, they would require a sentinel "No kid" kid
#    and a sentinel parent perhaps called "Employee".
# 4.1)
# 5) Parents aren't always in the same family, and sometimes there's many.
# 6) Sometimes children share siblings with parents that are not theirs as well.
#    Said another way, not all siblings share the same parents, such as step- and half- siblings.
# 7) Orphan children are assumed to use a sentinel guarian-like parent account.

# class SimilarProductRelation < ActiveRecord::Base
#   belongs_to :product
#   belongs_to :similar_product, class_name: "Product"
# end

# class Product < ApplicationRecord
#   # self being the "origin"
#   has_many :similar_products_relations, source: :product_id, class_name: "SimilarProductRelation"
#   has_many :similar_products, class_name: "Product", through: :similar_products_relations

#   # self being the "destination"
#   has_many :similar_products_relations_as, source: :similar_product_id, class_name: "SimilarProductRelation"
#   has_many :similar_products_as, class_name: "Product", through: :similar_products_relations
# end

# POST 307 / -> incoming table
# GET /?some_params - relationship_timeline
ActiveRecord::Schema.define do
  # An evolution of carer->families. It's more like a calendar.
  create_table :relationship_timeline, force: true do |t|
    # State machine state & transition & event
    t.string     :state
    t.string     :transition
    t.json       :event
    
    t.integer :carer_id
    t.integer :kid_id
    t.integer :parent_id

    # HMAC key lifecycle is append-only for verification later. VFS Enforce later.
    # Could support including customer key too maybe.
    # t.string     :key
    # t.string     :signed_attributes, null: false, default: "created_at,state,change,last_seen_event_id"
    # t.string     :signature

    # t.references :event, foreign_key: true, null: false, index: true
    # t.references :similar_event, foreign_key: { to_table: :relationship_timeline }, null: false, index: true 

    # Used for MVCC-like concurrency control for clients
    t.integer :last_seen_event_id, null: false
    t.timestamps
  end
    # create_table :incoming, force: true do |t|
  #   # Just in case it's weird, we'll check if data is empty and look through raw.
  #   t.string :raw
  #   t.json :data
    
  #   # SQLite3 locks to a single writer, I'd use row-level security and locking elsewhere.
  #   # Null is like 'stop retrying', values are arbitrary but are expected to
  #   # decrease as the incoming data is handled.
  #   t.integer :remainder, default: 100
  #   t.json :output, null: false, default: "{error: null}"
  #   t.timestamps
  # end

  # Ideally would be a virtual table over the timeline.
  # create_table :person, force: true do |t|
  #   t.json :info
  #   t.timestamps
  # end

  # migration
  # d INT GENERATED ALWAYS AS (json_extract(body, '$.d')) VIRTUAL);
end

# class Person < ActiveRecord::Base
#   set :table_name, :person
# end
# class Relationship
#   set :table_name, :relationship_timeline
#   #scope :, ->{}
# end

# class TestApp < Rails::Application
#   secrets.secret_token    = "secret_token"
#   secrets.secret_key_base = "secret_key_base"

#   config.logger = Logger.new($stdout)
#   Rails.logger = config.logger

#   routes.draw do
#     resources :primary_categories, only: :index
#   end
# end

# class PrimaryCategoriesController < ActionController::Base
#   include Rails.application.routes.url_helpers

#   def index
#     @primary_categories = Category.primaries
#     render inline: "# of primary categories: <%= @primary_categories.count %>"
#   end

#   def db
#       send_file(DB_FILE)
#   end
# end
  # FactoryGirl.define do
  #   factory :book do
  #     name "Thing Explainer: Complicated Stuff in Simple Words"
  
  #     trait :with_primary_category do
  #       after(:create) do |book, _|
  #         book.categorizations << Categorization.create!(category: create(:science_category), book: book, primary: true)
  #       end
  #     end
  
  #     trait :with_secondary_category do
  #       after(:create) do |book, _|
  #         book.categorizations << Categorization.create!(category: create(:fun_facts_category), book: book, primary: false)
  #       end
  #     end
  #   end
  
  #   factory :science_category, class: Category do
  #     name "Science & Scientists"
  #   end
  
  #   factory :fun_facts_category, class: Category do
  #     name "Trivia & Fun Facts"
  #   end
  # end
  
  # require "minitest/autorun"
  
  # class CategoryTest < Minitest::Test
  #   def test_primary_categories
  #     FactoryGirl.create(:book, :with_primary_category, :with_secondary_category)
  
  #     assert_equal [Category.find_by_name('Science & Scientists')], Category.primaries
  #   end
  # end
  
  # class PrimaryCategoriesTest < Minitest::Test
  #   include Rack::Test::Methods
  
  #   def test_index
  #     get "/primary_categories"
  
  #     assert last_response.ok?
  #     assert_equal "# of primary categories: 1", last_response.body
  #   end
  
  #   private
  
  #   def app
  #     Rails.application
  #   end
  # end