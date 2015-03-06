# coding: utf-8
#

require 'httparty'
require 'jwt'

require 'cddaiv/log'

module CDDAIV
  class OAuthError < RuntimeError; end

  module OAuth
    include CDDAIV::Log

    Result = Struct.new(:login, :email, :error)
    class Result
      def success?; self.error.nil?; end
    end

    @@creds = Hash.new

    def self.options
      @@creds
    end

    def self.options=(hsh)
      @@creds = hsh
    end

    def self.request(&blk)
      raise ArgumentError, 'No block given' if blk.nil?

      begin
        yield
      rescue RuntimeError => e
        log :error, 'OAuth network request error'
        log :error, e.to_s
        log :debug, e.backtrace.join("\n")
        raise OAuthError, 'OAuth network request error.'
      end
    end

    def self.auth(service, params, args = {})
      unless respond_to? "auth_#{service}"
        log :warn, "No such OAuth service '#{service}'"
        return nil
      end

      send("auth_#{service}", params, args)
    end

    def self.auth_github(params, args)
      unless params[:code]
        log :warn, 'GitHub callback without auth code'
        return Result.new(nil, nil, 'GitHub callback without auth code.')
      end
      code = params[:code]

      creds = @@creds[:github]
      log :debug, 'GitHub POST /access_token'
      begin
        res = self.request do
          HTTParty.post('https://github.com/login/oauth/access_token',
                        body: {client_id: creds[:id], client_secret: creds[:secret],
                               code: code},
                        headers: {'Accept' => 'application/json'})
        end
      rescue OAuthError => e
        return Result.new(nil, nil, e.to_s)
      end

      if res.code != 200 || !res.has_key?('access_token')
        log :error, 'GitHub callback error on POST /access_token'
        log :debug, res
        return Result.new(nil, nil, "Couldn't get access token, sorry.")
      end
      token = res['access_token']

      log :debug, 'GitHub GET /user'
      begin
        res = self.request do
          HTTParty.get('https://api.github.com/user', 
                       query: {access_token: token},
                       headers: {'User-Agent' => 'drbig/cddaiv'})
        end
      rescue OAuthError => e
        return Result.new(nil, nil, e.to_s)
      end

      if res.code != 200 || !res.has_key?('login')
        log :error, 'GitHub callback error on GET /user'
        log :debug, res
        return Result.new(nil, nil, "Couldn't access your profile, sorry.")
      end
      login = res['login']

      if res.has_key? 'email'
        email = res['email']
      else
        log :debug, 'GitHub GET /user/emails'
        begin
          res = self.request do
            HTTParty.get('https://api.github.com/user/emails',
                         query: {access_token: token},
                         headers: {'User-Agent' => 'drbig/cddaiv'})
          end
        rescue OAuthError => e
          return Result.new(nil, nil, e.to_s)
        end

        if res.code != 200 
          log :error, 'GitHub callback error on GET /user/emails'
          log :debug, res
          return Result.new(nil, nil, "You don't seem to have a public email and I couldn't get any other.")
        end

        emails = res.select {|h| h['verified'] }
        unless emails.any?
          log :error, 'GitHub callback no verified email found'
          log :debug, res
          return Result.new(nil, nil, "Seems you don't have any verified email anywhere.")
        end

        email = emails.first['email']
      end

      Result.new(login, email)
    end

    def self.auth_google(params, args)
      if params[:state].nil? || args[:token].nil?
        log :warn, 'Google callback without token/state'
        return Result.new(nil, nil, 'Sorry, something went wrong.')
      end
      state = params[:state]
      token = args[:token]

      if state != token
        log :error, "Google callback token mismatch: #{token} != #{state}"
        return Result.new(nil, nil, 'Security token mismatch, sorry.')
      end

      unless params[:code]
        log :warn, 'Google callback without auth code'
        return Result.new(nil, nil, 'Google callback without auth code.')
      end
      code = params[:code]

      creds = @@creds[:google]
      log :debug, 'Google POST /token'
      begin
        res = self.request do
          HTTParty.post('https://www.googleapis.com/oauth2/v3/token',
                            body: {client_id: creds[:id], client_secret: creds[:secret],
                                   code: code, redirect_uri: creds[:uri],
                                   grant_type: :authorization_code},
                                   headers: {'Accept' => 'application/json'})
        end
      rescue OAuthError => e
        return Result.new(nil, nil, e.to_s)
      end

      if res.code != 200 || !res.has_key?('id_token')
        log :error, 'Google callback error on POST /token'
        log :debug, res
        return Result.new(nil, nil, "Couldn't get your email, sorry.")
      end

      begin
        data = JWT.decode(res['id_token'], nil, false).first
      rescue JWT::DecodeError => e
        log :error, e.to_s
        log :debug, e.backtrace.join("\n")
        return Result.new(nil, nil, 'Your ID token seems to be broken, sorry.')
      end

      unless data['email_verified']
        log :error, 'Google callback no verified email found'
        log :debug, data
        return Result.new(nil, nil, "Seems you don't have any verified email anywhere.")
      end

      email = data['email']
      login = email.split('@').first

      Result.new(login, email, nil)
    end
  end
end
