# coding: utf-8
#

require 'addressable/uri'
require 'httparty'

module CDDAIV
  module Github
    AGENT   = 'drbig/cddaiv'
    REPO    = 'CleverRaven/Cataclysm-DDA'
    ISSUES  = "https://api.github.com/repos/#{REPO}/issues"

    RawIssue = Struct.new(:id, :num, :title, :open, :from, :until)

    def self.get_issues(since, state = :all)
      uri = Addressable::URI.parse(ISSUES)
      query = Hash.new
      query[:since] = since.utc.iso8601 if since
      query[:state] = 'open'    if state == :open
      query[:state] = 'closed'  if state == :closed

      get(uri.to_s).collect do |e|
        RawIssue.new(e['id'], e['number'], e['title'], e['state'] == 'open',
                     DateTime.parse(e['created_at']),
                     e['closed_at'] ? DateTime.parse(e['closed_at']) : nil)
      end
    end

    private
    def self.get(url)
      HTTParty.get(url, headers: {'User-Agent' => AGENT})
    end
  end
end
