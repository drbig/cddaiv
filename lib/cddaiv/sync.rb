# coding: utf-8
#

require 'cddaiv/github'
require 'cddaiv/log'
require 'cddaiv/model'

module CDDAIV
  module Database
    @last_update = nil

    def self.update!(opts = {})
      since = opts[:since] || @last_update
      start = Time.now

      log :info, 'Updating issues database...'
      opened = 0
      Github.get_issues(since, :open).each do |ri|
        if i = Issue.get(ri.id)
          i.attributes = ri.to_h
        else
          opened += 1
          i = Issue.create(ri.to_h)
        end
        i.save!
      end
      closed = 0
      Github.get_issues(since, :closed).each do |ri|
        if i = Issue.get(ri.id)
          closed += 1 if i.open
          i.attributes = ri.to_h
          i.open = false
          i.save!
        end
      end
      log :debug, "New: #{opened}, closed: #{closed} issues"
      log :info, 'Database update finished'

      @last_update = start
    end

    def self.clean!(opts = {})
    end
  end
end
