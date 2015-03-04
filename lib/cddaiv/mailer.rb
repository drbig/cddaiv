# coding: utf-8
#

require 'pony'
require 'thread'

require 'cddaiv/log'

module CDDAIV
  module Mailer
    include CDDAIV::Log

    Status = Struct.new(:state, :sent, :errors)
    Mail = Struct.new(:to, :subject, :body, :when, :tries)

    @@queue = Array.new
    @@mutex = Mutex.new
    @@sent = 0
    @@errors = 0
    @@thread = nil

    def self.options
      Pony.options
    end

    def self.options=(hsh)
      Pony.options = hsh
    end

    def self.send(to, subject, body)
      log :debug, "Enqueuing email to '#{to}'"
      @@mutex.synchronize do
        @@queue.push(Mail.new(to, subject, body, Time.now, 3))
        # return queue length
        @@queue.length
      end
    end

    def self.status
      if @@thread
        state = case @@thread.status
                when 'sleep'
                  'Running (sleeping)'
                when 'run'
                  'Running (executing)'
                when 'aborting'
                  'Running (aborting)'
                when false
                  'Exited'
                else
                  'Died'
                end
      else
        state = 'Not started'
      end

      Status.new(state, @@sent, @@errors)
    end

    def self.run!
      log :info, 'Starting mailer thread'
      @@thread = Thread.new do
        while true
          if mail = @@mutex.synchronize { @@queue.shift }
            log :info, "Sending email to '#{mail.to}'"
            log :debug, "Subject: '#{mail.subject}', enqueued: #{mail.when.strftime('%Y-%m-%d %H:%M:%S %Z')}"
            log :debug, "Body legth: #{mail.body.length}"
            begin
              Pony.mail(to: mail.to, subject: mail.subject, body: mail.body)
            rescue StandardError => e
              @@mutex.synchronize { @@errors += 1 }
              log :error, "Mail not sent: '#{e.to_s}'"
              if mail.tries < 1
                log :error, 'Mail will not be resend'
              else
                mail.tries -= 1
                log :warn, "Will try to resend the mail later (#{mail.tries} left)"
                @@mutex.synchronize { @@queue.push(mail) }
              end
            else
              @@mutex.synchronize { @@sent += 1 }
              log :info, 'Mail sent successfully'
            end
          end
          sleep(10)
        end
      end
      @@thread.abort_on_exception = true

      @@thread
    end
  end
end
