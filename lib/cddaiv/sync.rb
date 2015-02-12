# coding: utf-8
#

require 'chronic'

require 'cddaiv/github'
require 'cddaiv/log'
require 'cddaiv/model'

module CDDAIV
  module Database
    @@last_update = nil

    def self.last_update
      @@last_update
    end

    # Sync issue list with GitHub
    def self.update!(opts = {})
      since = opts[:since] || @@last_update
      start = Time.now

      log :info, 'Updating issues database...'
      opened = 0
      updated = 0
      Github.get_issues(since, :open).each do |ri|
        if i = Issue.get(ri.id)
          if (i.title != ri.title) || (i.updated != ri.updated)
            i.update(title: ri.title, updated: ri.updated) ? updated += 1 : log(:error, "Couldn't update issue #{i.id}")
          end
        else
          i = Issue.new(ri.to_h)
          i.save ? opened += 1 : log(:error, "Couldn't save issue #{i.id}")
        end
      end
      closed = 0
      Github.get_issues(since, :closed).each do |ri|
        if i = Issue.get(ri.id)
          if (i.title != ri.title) || (i.updated != ri.updated)
            i.update(title: ri.title, updated: ri.updated) ? updated += 1 : log(:error, "Couldn't update issue #{i.id}")
          end
          if i.open
            i.update(open: false) ? closed += 1 : log(:error, "Couldn't update issue #{i.id}")
          end
        end
      end
      log :debug, "New: #{opened}, updated: #{updated}, closed: #{closed} issues"
      log :info, 'Database update finished'

      @@last_update = start
    end

    # Remove closed issues
    def self.clean_issues!(opts = {})
      keep = opts[:keep] || 100

      log :info, 'Cleaning closed issues...'
      closed = Issue.all(open: false, order: [:until.desc])
      if closed.count < keep
        log :debug, 'Nothing to clean'
        log :info, 'Issue cleaning finished'
        return 0
      end

      rest = closed.slice(keep, closed.length)
      if rest.all.destroy
        log :debug, "Removed #{rest.length} old issues"
      else
        log :error, 'Error removing old issues'
      end
      log :info, 'Issue cleaning finished'

      rest.length
    end

    # Remove not verified users
    def self.clean_nv_users!(opts = {})
      maxdelta = opts[:maxdelta] || '2 days ago'
      stamp = Chronic.parse(maxdelta)

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
    def self.clean_ia_users(opts = {})
      maxdelta = opts[:maxdelta] || '1 year ago'
      stamp = Chronic.parse(maxdelta)

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
