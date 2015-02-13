# coding: utf-8
#

require 'chronic'

require 'cddaiv/github'
require 'cddaiv/log'
require 'cddaiv/model'

module CDDAIV
  module Database
    @@last_update = nil
    @@options = {
      keep: 100,
      stale: '1 week ago',
      verified: '2 days ago',
      active: '6 months ago',
    }

    def self.options
      @@options
    end

    def self.options=(hsh)
      @@options.merge!(hsh)
    end

    # Sync issue list with GitHub
    def self.update!(since = nil)
      since ||= @@last_update
      maxdelta = @@options[:stale] || '1 week ago'
      stamp = Chronic.parse(maxdelta).to_datetime
      start = Time.now

      log :info, 'Updating issues database...'
      created = 0
      updated = 0
      Github.get_issues(since, :open).each do |ri|
        if i = Issue.get(ri.id)
          i.update(ri.to_h) ? updated += 1 : log(:error, "Couldn't update issue #{i.id}")
        else
          i = Issue.new(ri.to_h)
          i.save ? created += 1 : log(:error, "Couldn't save issue #{i.id}")
        end
      end
      closed = 0
      Github.get_issues(since, :closed).each do |ri|
        if i = Issue.get(ri.id)
          closed += 1 unless ri.open
          state = ri.to_h
          state[:stale] = false
          i.update(state) ? updated += 1 : log(:error, "Couldn't update issue #{i.id}")
        end
      end
      log :debug, "New: #{created}, updated: #{updated}, closed: #{closed} issues"

      stale_yes = 0
      stale_not = 0
      Issue.all(open: true).each do |i|
        if i.updated < stamp
          i.update(stale: true) ? stale_yes += 1 : log(:error, "Couldn't update issue #{i.id}")
        else
          i.update(stale: false) ? stale_not += 1 : log(:error, "Couldn't update issue #{i.id}")
        end
      end
      log :debug, "Stale issues: +#{stale_yes} -#{stale_not}"
      log :info, 'Database update finished'

      @@last_update = start
    end

    # Remove closed issues
    def self.clean_issues!
      keep = @@options[:keep] || 100

      log :info, 'Cleaning closed issues...'
      closed = Issue.all(open: false, order: [:until.desc])
      if closed.count < keep
        log :debug, 'Nothing to clean'
        log :info, 'Issue cleaning finished'
        return 0
      end

      deleted = 0
      closed.slice(keep, closed.length).each do |i|
        i.votes.all.destroy || log(:error, "Couldn't delete votes for issue #{i.id}")
        i.destroy ? deleted += 1 : log(:error, "Couldn't delete issue #{i.id}")
      end
      log :debug, "Deleted #{deleted} issues"
      log :info, 'Issue cleaning finished'

      deleted
    end

    # Remove not verified users
    def self.clean_nv_users!
      maxdelta = @@options[:verified] || '2 days ago'
      stamp = Chronic.parse(maxdelta).to_datetime

      log :info, 'Cleaning not verified users...'
      removed = 0
      User.all(verified: false).each do |u|
        unless u.token
          log :error, "User '#{u.login}' has no token present"
          next
        end

        if u.token.when < stamp
          log :debug, "Removing user '#{u.login}', token dated #{u.token.when.strftime('%Y-%m-%d %H:%M:%S %Z')}"
          u.votes.all.destroy || log(:error, "Error removing votes for user '#{u.login}'")
          u.token.destroy || log(:error, "Error removing token for user '#{u.login}'")
          if u.destroy
            log :debug, "Removed user '#{u.login}'"
            removed += 1
          else
            log :error, "Error removing user '#{u.login}'"
          end
        end
      end
      log :debug, "Removed #{removed} users"
      log :info, 'Not verified users cleaning finished'

      removed
    end

    # Remove inactive users
    def self.clean_ia_users!
      maxdelta = @@options[:active] || '6 months ago'
      stamp = Chronic.parse(maxdelta).to_datetime

      log :info, 'Cleaning inactive users...'
      removed = 0
      User.all(:seen.lt => stamp).each do |u|
        log :debug, "Removing user '#{u.login}', last seen #{u.seen.strftime('%Y-%m-%d %H:%M:%S %Z')}"
        u.votes.all.destroy || log(:error, "Error removing votes for user '#{u.login}'")
        if u.token
          u.token.destroy || log(:error, "Error removing token for user '#{u.login}'")
        end
        if u.destroy
          log :debug, "Removed user '#{u.login}'"
          removed += 1
        else
          log :error, "Error removing user '#{u.login}'"
        end
      end
      log :debug, "Removed #{removed} users"
      log :info, 'Inactive users cleaning finished'

      removed
    end
  end
end
