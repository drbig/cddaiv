#!/usr/bin/env ruby
# coding: utf-8
#

$LOAD_PATH.unshift File.join(File.dirname(__FILE__), '../lib')

require 'chronic'
require 'thor'

require 'cddaiv/model'

class CLI < Thor
  include CDDAIV

  @@config = {
    'db' => 'sqlite://cddaiv.bin',
  }

  desc 'seed', 'initialise the databases'
  option :db
  def seed
    cfg = @@config.merge!(options)

    require 'cddaiv/sync'

    Database.setup!(cfg['db'], migrate: true)
    Database.update!
  end

  desc 'update', 'update the issues database'
  option :since
  option :db
  def update
    cfg = @@config.merge(options)

    require 'cddaiv/sync'

    Database.setup!(cfg['db'])
    Database.update!(cfg)
  end
end

CLI.start(ARGV)
