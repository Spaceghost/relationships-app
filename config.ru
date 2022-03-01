#!/usr/bin/env ruby
# warn_indent: true
# encoding: UTF-8
# frozen_string_literal: true
# shareable_constant_value: literal
#
# This file is has multiple modes:
# 1) Server - `rackup` this file to bootstrap the database and start a pool of workers.
# 2) Executable - `ruby ./config.ru` Bootstraps sqlite3 database with timeline and 
#    Runs workers against sqlite3 database incoming and relationship_events tables and exits.
# 3) Test - `DB_FILE_PATH=':memory:' ./config.ru`
# Run this file with:
#   rackup -p 3000

# TODO: Use my VFS fork of spaceghost/sqlite3-ruby to append this database to this file.
DB_FILE_PATH = ENV.fetch("DB_FILE_PATH", "./modern_solutions.db")

begin
  require "bundler/inline"
rescue LoadError => e
  $stderr.puts "Bundler version 1.10 or later is required. Please update your Bundler"
  raise e
end
  
gemfile(true) do
  source "https://rubygems.org"

  gem "rails"
  gem "activerecord"
  gem "activejob"
  gem "sqlite3"
  gem "puma"
  gem "faker"

  # TODO: Integrate these gems
  # Reminder: Set papertrail's serializer to JSON instead of default YAML.
  gem "papertrail"             # https://github.com/paper-trail-gem/paper_trail
  # gem "hairtrigger"         # https://github.com/jenseng/hair_trigger
  # gem "stateful_controller" # https://github.com/coldnebo/stateful_controller
  # gem "json-schema"         # https://github.com/voxpupuli/json-schema
  # I'd use json-schema here to call attention to when the shape of data changes.
  # We're using sqlite3 as a fun indexable relational document store here.
  # As long as the same inputs generate the same outputs, we can register the
  # '#validate' method as a SQL function in SQLite3. See The HMAC section at the end.
end

require "active_record"
require "action_controller/railtie"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: DB_FILE_PATH)
ActiveRecord::Base.logger = Logger.new(STDOUT)

# Everyone is somebody else's kid.
# The difference is in these three primary cases.
#
# 1) A parent will have no parent : but will have some kids
# 2) A carer may have some parents: and may have some kids
# 3) A kid will have parents      : but has no kids
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
# 4) Parents aren't always in the same family, and sometimes there's many.
# 5) Sometimes children share siblings with parents that are not theirs as well.
#    Said another way, not all siblings share the same parents, such as step- and half- siblings.
# 6) Orphan-like children are assumed to use a sentinel guarian-like parent account.

# POST 307 / -> incoming
# GET /?some_params -> relationship_timeline
# GET /app -> __FILE__
# GET /db -> __DB__
ActiveRecord::Schema.define do
  create_table :incoming, force: true do |t|
    # Just in case it's weird, we'll check if data is empty and look through raw.
    t.string :raw
    t.json :data

    # SQLite3 locks to a single writer, I'd use row-level security and locking elsewhere.
    # Null is like 'stop retrying', values are arbitrary but are expected to
    # decrease as the incoming data is handled.
    # TODO: Use with workers to transform the data and insert into the relationship_timeline
    t.integer :remainder, default: 100
    t.json :output, null: false, default: "{error: null}"

    t.timestamps
  end

  # Generated columns; https://www.sqlite.org/gencol.html
  # Here we reach into the json and build indexable fields, albeit readonly.
  # Change the JSON to change the row value. Neat, right?
  %w|carer_id kid_id parent_id|.each do |name|
    connection.execute "ALTER TABLE incoming ADD COLUMN #{name} INT GENERATED ALWAYS AS (json_extract(data, '$.#{name}')) VIRTUAL;"
  end

  # An evolution of carer->families. It's more like calendar+documentdb state machine.
  create_table :relationship_timeline, force: true do |t|
    # TODO: State machine state & transition & event
    t.string     :state
    t.string     :transition
    t.json       :event

    # TODO: HMAC key lifecycle is append-only for verification later. VFS Enforce later.
    # Could support including customer key too maybe.
    # t.string     :keyring
    # t.string     :signed_attributes, null: false, default: "created_at,state,change,last_seen_event_id"
    # t.string     :signature

    # TODO: Build indexes for these tables
    # TODO: Used for MVCC-like concurrency control for 'offline' clients.
    # t.integer :last_seen_event_id, null: false
    t.timestamps
  end

  # Generated columns, this time indexing into the relationship timeline.
  %w|carer_id kid_id parent_id|.each do |name|
    connection.execute "ALTER TABLE relationship_timeline ADD COLUMN #{name} INT GENERATED ALWAYS AS (json_extract(event, '$.#{name}')) VIRTUAL;"
  end

  # Ideally would be a virtual table over the timeline.
  # However, here it's a fact table. It becomes important if it holds data
  # that's unable to be derived from other sources.
  create_table :person, force: true do |t|
    t.json :info
    t.timestamps
  end
  %w|name carer_id kid_id parent_id|.each do |name|
    connection.execute "ALTER TABLE person ADD COLUMN #{name} INT GENERATED ALWAYS AS (json_extract(info, '$.#{name}')) VIRTUAL;"
  end
  connection.execute "ALTER TABLE person ADD COLUMN _id INT GENERATED ALWAYS AS (json_extract(info, '$.id')) VIRTUAL;"
end

# TODO: State-machine driven models with papertrail versions stored in the relationship_timeline
# class Person < ActiveRecord::Base
#   set :table_name, :person
# end
# class Relationship
#   set :table_name, :relationship_timeline
# end

class ModernProblems < Rails::Application
  # Toy app, use proper secret storage.
  secrets.secret_token    = "secret_token"
  secrets.secret_key_base = "secret_key_base"
  config.eager_load = true # necessary to silence warning

  # Need all these for codespace development environment
  config.consider_all_requests_local = true
  config.hosts = nil
  config.action_dispatch.default_headers = { 'X-Frame-Options' => 'ALLOWALL' }
  config.action_controller.default_protect_from_forgery = true
  
  # TODO: Use SQLite3 for logger.
  config.logger = Logger.new($stdout)
  Rails.logger = config.logger

  routes.append do
    root to: 'single#desc'
    get :desc, to: 'single#desc', as: :get_desc
    get :app,  to: 'single#app',  as: :get_app
    get :db,   to: 'single#db',   as: :get_db
    
    # %w|app db desc|.each do |action|
    #   get action, to: "single##{action}", as: :"get_#{action}"
    # end
    # # Or reusably
    # args_for = Hash.new do |_,k|
    #   [k.to_sym, to: "single##{k}"", as: :"get_#{action}"]
    # end
    # %w|app db desc|.each do |action|
    #   get *args_for(action)
    # end
  end
end

class SingleController < ActionController::Base
  include Rails.application.routes.url_helpers

  def desc 
    render plain: <<~EOS
    Put the README here.
    EOS
  end
  def app;send_file(__FILE__);end
  def db;send_file(DB_FILE_PATH);end
end

# TODO: Add HMAC functions to sqlite3 user functions
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

require 'active_job'
ActiveJob::Base.queue_adapter = ActiveJob::QueueAdapters::InlineAdapter.new
class LinkJob < ActiveJob::Base
  queue_as :link

  def perform(record)
  end
end
class TransformJob < ActiveJob::Base
  queue_as :transform
  def perform(record)
  end
end

ModernProblems.initialize!

# TODO: Rework this or stop using it. @spaceghost @weekly
if __FILE__.eql? $0
  require "minitest/autorun"

  class ModernSolutionsTest  < Minitest::Test

    DATA.each_line do |line|
      name, *code = line.split(" ")
      class_eval <<-END
        def #{name}; #{code.join("")}; end
      END
    end
  end
end

# TODO: Add single-shot CLI mode @spaceghost @weekly

run ModernProblems
# TODO: Use DATA for test cases. @spaceghost @weekly
__END__