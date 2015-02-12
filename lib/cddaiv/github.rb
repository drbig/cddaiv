# coding: utf-8
#

require 'addressable/uri'
require 'httparty'

require 'cddaiv/log'

module CDDAIV
  module Github
    include CDDAIV::Log

    AGENT   = 'drbig/cddaiv'
    REPO    = 'CleverRaven/Cataclysm-DDA'
    ISSUES  = "https://api.github.com/repos/#{REPO}/issues"

    RawIssue = Struct.new(:id, :num, :title, :type, :open, :from, :until, :updated)

    def self.get_issues(since, state = nil)
      uri = Addressable::URI.parse(ISSUES)
      query = Hash.new
      query[:since] = since.utc.iso8601 if since
      query[:state] = state.to_s if state
      uri.query_values = query

      log :debug, 'Fetching issues from GitHub'
      issues = get(uri.to_s).collect do |e|
        RawIssue.new(e['id'], e['number'], e['title'],
                     e.has_key?('pull_request') ? :pr : :issue,
                     e['state'] == 'open',
                     DateTime.parse(e['created_at']),
                     e['closed_at'] ? DateTime.parse(e['closed_at']) : nil,
                     DateTime.parse(e['updated_at']))
      end
      log :debug, "Fetched #{issues.length} issues"
      issues
    end

    private
    def self.get(url)
      log :debug, "Get query for '#{url}'"
      HTTParty.get(url, headers: {'User-Agent' => AGENT})
    end
  end
end
