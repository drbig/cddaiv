# coding: utf-8
#

require 'digest/sha1'
require 'dm-core'
require 'dm-types'
require 'dm-validations'

require 'cddaiv/log'

module CDDAIV
  class User
    include DataMapper::Resource

    property :login, String, key: true, length: 3..32
    property :pass, String, required: true, length: 40
    property :salt, String, required: true, length: 6
    property :email, String, required: true, format: :email_address, length: 6..254
    property :verified, Boolean, default: false, required: true
    property :since, DateTime, default: Proc.new { DateTime.now }, required: true
    property :seen, DateTime

    has n, :votes
    has 1, :token

    def pass=(plain)
      return errors.add(:pass, 'Password too short (min. 6 characters)') if plain.length < 6
      self.salt = rand(1_000_000).to_s
      # we need this otherwise we get a lovely loop of pass=() calls :)
      attribute_set(:pass, Digest::SHA1.hexdigest(plain + salt))
    end

    def valid_pass?(plain)
      Digest::SHA1.hexdigest(plain + salt) == pass
    end
  end

  class Token
    include DataMapper::Resource

    property :id, Serial, key: true
    property :value, String, required: true, length: 40
    property :when, DateTime, default: Proc.new { DateTime.now }, required: true

    belongs_to :user

    # datamapper is retarded too
    # will need to call this explicitly before saving
    def generate
      salt = rand(1_000_000).to_s
      self.value = Digest::SHA1.hexdigest(user.login + user.email + salt)
    end
  end

  class Issue
    include DataMapper::Resource

    property :id, Integer, key: true
    property :num, Integer, required: true
    property :title, String, required: true, length: 1..256
    property :open, Boolean, default: true, required: true
    property :from, DateTime, required: true
    property :until, DateTime
    property :score, Integer, default: 0, required: true

    has n, :votes
  end

  class Vote
    include DataMapper::Resource

    property :id, Serial, key: true
    property :dir, Enum[:up, :down], required: true
    property :when, DateTime, default: Proc.new { DateTime.now }, required: true

    belongs_to :user, key: true
    belongs_to :issue, key: true
  end

  DataMapper.finalize

  module Database
    include CDDAIV::Log

    def self.setup!(uri, migrate: false)
      log :info, 'Opening database'
      log :debug, "Database URI '#{uri}'"
      DataMapper.setup(:default, uri)
      if migrate
        log :debug, 'Migrating database'
        require 'dm-migrations'
        DataMapper.auto_migrate!
      end
    end
  end
end
