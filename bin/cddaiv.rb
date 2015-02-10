#!/usr/bin/env ruby
# coding: utf-8
#

$LOAD_PATH.unshift File.join(File.dirname(__FILE__), '../lib')

require 'chronic'
require 'thor'

require 'cddaiv/model'
require 'cddaiv/log'

class CLI < Thor
  class_option :db, type: :string, default: 'sqlite://cddaiv.bin', desc: 'Database URI'
  class_option :verbose, type: :boolean, default: false, desc: 'Enable debug logging'
  class_option :log, type: :string, desc: 'Log to FILE'

  desc 'seed', 'Migrate and seed the database.'
  def seed
    CDDAIV::Log.default!(options)

    require 'cddaiv/sync'

    CDDAIV::Database.setup!(options[:db], migrate: true)
    CDDAIV::Database.update!
  end

  desc 'update', 'Update the issues database.'
  method_option :since, type: :string, desc: 'Update since the given date'
  def update
    cfg = options.dup
    cfg[:since] = Chronic.parse(cfg[:since]) if cfg[:since]

    CDDAIV::Log.default!(cfg)

    require 'cddaiv/sync'

    CDDAIV::Database.setup!(cfg[:db])
    CDDAIV::Database.update!(cfg)
  end
end

CLI.start(ARGV)
