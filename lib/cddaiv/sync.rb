# coding: utf-8
#

require 'cddaiv/github'
require 'cddaiv/model'

module CDDAIV
  module Database
    @last_update = nil

    def self.update!(opts = {})
      since = opts[:since] || @last_update

      Github.get_issues(since, :open).each do |ri|
        i = Issue.first_or_create(id: ri.id)
        i.attributes = ri.to_h
        i.save
      end
    end

    def self.clean
    end
  end
end
