# coding: utf-8
#

require 'digest/sha1'
require 'dm-core'
require 'dm-validations'

module CDDAIV
  class User
    include DataMapper::Resource

    property :login, String, key: true, length: 3..32
    property :pass, String, required: true, length: 40
    property :salt, Integer, required: true
    property :email, String, required: true, format: :email_address, length: 6..64
    property :since, DateTime, default: Proc.new { DateTime.now }, required: true
    property :seen, DateTime

    has n, :votes

    def password=(plain)
      raise ArgumentError('Password too short') if plain.length < 6
      salt = rand(1_000_000).to_s
      attribute_set(:pass, Digest::SHA1.hexdigest(plain + salt))
      attribute_set(:salt, salt)
    end

    def valid_pass?(plain)
      salt = attribute_get(:salt)
      pass = attribute_get(:pass)
      Digest::SHA1.hexdigest(plain + salt) == pass
    end
  end

  class Issue
    include DataMapper::Resource

    property :id, Integer, key: true
    property :num, Integer, required: true
    property :title, String, required: true
    property :open, Boolean, default: true, required: true
    property :from, DateTime, required: true
    property :until, DateTime

    has n, :votes
  end

  class Vote
    include DataMapper::Resource

    belongs_to :user, key: true
    belongs_to :issue, key: true

    property :when, DateTime, default: Proc.new { DateTime.now }, required: true
  end

  DataMapper.finalize

  module Database
    def self.setup!(uri, migrate: false)
      DataMapper.setup(:default, uri)
      if migrate
        require 'dm-migrations'
        DataMapper.auto_migrate!
      end
    end
  end
end
