#!/usr/bin/env ruby
# coding: utf-8
#

$LOAD_PATH.unshift File.join(File.dirname(__FILE__), '../lib')

require 'chronic'
require 'thor'

require 'cddaiv/model'
require 'cddaiv/log'
require 'cddaiv/version'

# for better output
STDOUT.sync = true
STDERR.sync = true

class CLI < Thor
  class_option :db, type: :string, default: 'sqlite:///tmp/cddaiv.bin', desc: 'Database URI'
  class_option :verbose, type: :boolean, default: false, desc: 'Enable debug logging'
  class_option :log, type: :string, desc: 'Log to FILE'

  desc 'seed', 'Migrate and seed the database.'
  method_option :user, type: :boolean, default: false, desc: 'Add test user'
  def seed
    CDDAIV::Log.default!(options)

    require 'cddaiv/sync'
    CDDAIV::Database.setup!(options[:db], migrate: true)
    CDDAIV::User.new(login: 'test', pass: 'password', email: 'test@localhost', verified: true).save! if options[:user]
    CDDAIV::Database.update!
  end

  desc 'update', 'Update the issues database.'
  method_option :since, type: :string, desc: 'Update since the given date'
  def update
    CDDAIV::Log.default!(options)

    cfg = options.dup
    cfg[:since] = Chronic.parse(cfg[:since]) if cfg[:since]
    require 'cddaiv/sync'
    CDDAIV::Database.setup!(cfg[:db])
    CDDAIV::Database.update!(cfg)
  end

  desc 'console', 'Run Pry console with database set up.'
  def console
    CDDAIV::Log.default!(verbose: true)

    require 'pry'
    CDDAIV::Database.setup!(options[:db])
    Pry.binding_for(CDDAIV).pry
  end

  desc 'webapp', 'Run the web interface.'
  method_option :host, type: :string, default: '127.0.0.1', desc: 'Bind hostname or IP address'
  method_option :port, type: :numeric, default: 8111, desc: 'Port to listen on'
  def webapp
    CDDAIV::Log.default!(options)
    CDDAIV::Database.setup!(options[:db])

    require 'cddaiv/mailer'
    # this is very temporary
    CDDAIV::Mailer.options = {
      from: 'drbig@kaer.eu.org',
      via: :smtp,
      via_options: {address: '78.8.120.130'}
    }
    CDDAIV::Mailer.run!

    require 'cddaiv/scheduler'
    CDDAIV::Scheduler.run!

    # fix for Thin
    cfg = options.dup
    cfg[:bind] = cfg[:host]
    require 'cddaiv/webapp'
    CDDAIV::WebApp.run!(cfg)
  end

  desc 'version', 'Show version and exit.'
  def version
    puts "CDDA IV #{CDDAIV::VERSION} - https://github.com/drbig/cddaiv"
  end
end

CLI.start(ARGV)
