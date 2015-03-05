# coding: utf-8
#

require 'thread'

require 'cddaiv/sync'
require 'cddaiv/log'

module CDDAIV
  module Scheduler
    include CDDAIV::Log

    Status = Struct.new(:name, :last, :next)

    @@sched = nil
    @@mutex = Mutex.new

    def self.status
      return [Status.new('Scheduler', 'Never', 'Never')] unless @@sched

      @@sched.jobs.map do |j|
        Status.new(j.tags.first,
                   j.last_time.nil? ? 'Never' : j.last_time.strftime('%Y-%m-%d %H:%M:%S %Z'),
                   j.next_time.nil? ? 'Never' : j.next_time.strftime('%Y-%m-%d %H:%M:%S %Z'))
      end
    end

    def self.run!(opts = {})
      log :info, 'Starting scheduler'

      require 'rufus-scheduler'
      @@sched = Rufus::Scheduler.new

      interval = opts[:update] || '1h'
      @@sched.every(interval, tag: 'Update database', mutex: @@mutex) do
        Database.update!
      end

      interval = opts[:clean_issues] || '1w'
      @@sched.every(interval, tag: 'Clean old issues', mutex: @@mutex) do
        Database.clean_issues!
      end

      interval = opts[:clean_nv_users] || '1d'
      @@sched.every(interval, tag: 'Clean non-verified users', mutex: @@mutex) do
        Database.clean_nv_users!
      end

      interval = opts[:clean_ia_users] || '1d'
      @@sched.every(interval, tag: 'Clean inactive users', mutex: @@mutex) do
        Database.clean_ia_users!
      end
    end
  end
end
