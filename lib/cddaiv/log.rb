# coding: utf-8
#

module CDDAIV
  module Log
    @@logger = nil

    def self.default!(opts = {})
      require 'logger'

      @@logger = Logger.new(opts[:log] || STDOUT)
      @@logger.level = opts[:verbose] ? Logger::DEBUG : Logger::INFO
      @@logger.formatter = Proc.new do |s, d, p, m|
        "#{d.strftime('%Y-%m-%d %H:%M:%S.%3N')} | #{s.ljust(5)} | #{m}\n"
      end

      @@logger
    end

    def self.logger=(obj)
      @@logger = obj
    end

    def self.logger
      @@logger
    end

    def self.included(base)
      class << base
        def log(level, msg)
          @@logger.send(level, msg) if @@logger
        end
      end
    end
  end
end
