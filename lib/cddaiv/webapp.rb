# coding: utf-8
#

require 'dm-serializer/to_json'
require 'sinatra/base'
require 'haml'
require 'json'
require 'httparty'
require 'jwt'

require 'cddaiv/log'
require 'cddaiv/model'
require 'cddaiv/mailer'
require 'cddaiv/scheduler'
require 'cddaiv/version'

# fix Sinatra logging retardation
class String
  def join(*_); self; end
end

module CDDAIV
  class WebApp < Sinatra::Base
    @@secret = 'this is not secure'
    @@oauth = nil

    def self.secret=(str)
      @@secret = str
    end

    def self.oauth=(hsh)
      @@oauth = hsh
    end

    configure do
      enable :static
      enable :logging
      enable :dump_errors
      enable :raise_errors
      
      set :root, File.join(File.dirname(__FILE__), '..', '..')
      set :public_dir, File.join(settings.root, 'static')
      set :views, File.join(settings.root, 'templates')
      set :sessions, expire_after: 2592000
      set :session_secret, @@secret
      set :haml, ugly: true
    end

    helpers do
      def email_verification(user)
        body = <<-eob
Hello #{user.login}!

You have registered/updated an account at the CDDA IV, please follow the link below:

http://#{request.host_with_port}/verify/#{user.login}/#{user.token.value}

to verify your account (you don't need to be logged in).

If you haven't registered with the CDDA IV just ignore this email.
If you think this is abuse or have other questions please contact the
admin by replying to this mail.

Best regards,
CDDA IV Mailer
        eob

        Mailer.send(user.email, 'CDDA IV - Account verification', body)
      end

      def email_reset(user, password)
        body = <<-eob
Hello #{user.login}!

You've requested a password reset. Here's your new password:

#{password}

Please login at http://#{request.host_with_port}/all and go to your
user tab and change the password to something more permanent,
preferably as soon as possible.

Best regards,
CDDA IV Mailer
        eob

        Mailer.send(user.email, 'CDDA IV - Password reset', body)
      end

      def email_password(user, password)
        body = <<-eob
Hello #{user.login}!

You've registered via an external service, and I have generated a
temporary password for you:

#{password}

Please remember to change it or delete this email if you plan on
using the sign-in option only. You can always reset your password
if you are logged in.

Best regards,
CDDA IV Mailer
        eob

        Mailer.send(user.email, 'CDDA IV - Temporary password', body)
      end

      def set_source
        uri = request.path
        uri += '?' + request.query_string unless request.query_string.empty?
        session[:source] = uri
      end
    end

    before do
      env['rack.logger'] = CDDAIV::Log.logger
      env['rack.errors'] = CDDAIV::Log.logger

      @user = session[:user] ? User.get(session[:user]) : nil
      @source = session[:source] || '/all'
      @oauth = @@oauth

      unless @token = session[:token]
        @token = session[:token] = ('A'..'Z').to_a.sample(12).join
      end

      @filter_type = :none
      @filter = Hash.new
      case params[:filter]
      when 'issue'
        @filter_type = :issue
        @filter[:type] = :issue
      when 'pr'
        @filter_type = :pr
        @filter[:type] = :pr
      when 'stale'
        @filter_type = :stale
        @filter[:stale] = true
      end
    end

    get '/' do
      redirect :all
    end

    get '/all' do
      set_source
      query = {open: true, order: [:from.desc]}.merge(@filter)
      @issues = Issue.all(query)
      @votes = @issues.map {|i| @user.votes(issue: i).first } if @user
      haml :all
    end

    get '/top' do
      set_source
      query = {open: true, limit: 30, order: [:score.desc]}.merge(@filter)
      @issues = Issue.all(query).to_a
      @votes = @issues.map {|i| @user.votes(issue: i).first } if @user
      haml :top
    end

    get '/bottom' do
      set_source
      query = {open: true, limit: 30, order: [:score.asc]}.merge(@filter)
      @issues = Issue.all(query).to_a
      @votes = @issues.map {|i| @user.votes(issue: i).first } if @user
      haml :bottom
    end

    get '/closed' do
      set_source
      query = {open: false, order: [:until.desc]}.merge(@filter)
      @issues = Issue.all(query).to_a
      haml :closed
    end

    get '/status' do
      database = {issues: Issue.count, votes: Vote.count, users: User.count}
      mailer = CDDAIV::Mailer.status
      scheduler = CDDAIV::Scheduler.status
      haml :status, locals: {database: database, mailer: mailer, scheduler: scheduler, ver: CDDAIV::VERSION}
    end

    post '/register' do
      if @user
        @error = "You're already logged in as '#{@user.login}'."
        return haml :fail
      end

      unless params[:login] && params[:passa] && params[:passb] && params[:email]
        @error = 'You need to fill in everything.'
        return haml :fail
      end

      if params[:login] != params[:login].gsub(/[^[A-za-z0-9]]/, '')
        @error = 'Login has to be plain-ASCII alphanumeric.'
        return haml :fail
      end

      if User.get(params[:login])
        @error = "Sorry, login '#{params[:login]}' is already taken."
        return haml :fail
      end

      if User.first(email: params[:email], verified: true)
        @error = 'Sorry, the e-mail you gave has already been used.'
        return haml :fail
      end

      unless params[:passa] == params[:passb]
        @error = 'Password mismatch. Please be more careful.'
        return haml :fail
      end

      user = User.new(login: params[:login], pass: params[:passa], email: params[:email])
      user.seen = DateTime.now
      unless user.save
        @error = user.errors.values.join(',') + '.'
        return haml :fail
      end

      token = Token.new(user: user)
      # TODO: i think this can be automated
      token.generate
      unless token.save
        @error = 'Failed to save the activation token.'
        @error += '<br>Failed to destroy the user.' unless user.destroy
        return haml :fail
      end

      user.token = token
      unless user.save
        @error = 'Failed to save the user with token.'
        @error += '<br>Failed to destroy the user.' unless user.destroy
        return haml :fail
      end

      email_verification(user)

      logger.info "New user '#{user.login}' registered"

      session[:user] = params[:login]
      redirect @source
    end

    post '/update' do
      unless @user
        @error = 'Not logged in.'
        return haml :fail
      end

      unless params[:pass] && (params[:email] || (params[:passa] && params[:passb]))
        @error = 'What were you expecting to achieve?'
        return haml :fail
      end

      unless @user.valid_pass? params[:pass]
        @error = 'Access denied.'
        return haml :fail
      end

      if params[:passa]
        if params[:passa] != params[:passb]
          @error = 'New password mismatch. Please be more careful.'
          return haml :fail
        end

        @user.pass = params[:passa]
      end

      unless params[:email].empty?
        @user.email = params[:email] 
        @user.verified = false
      end

      unless @user.save
        @error = @user.errors.values.join(',') + '.'
        return haml :fail
      end

      unless params[:email].empty?
        @user.token.destroy if @user.token

        token = Token.new(user: @user)
        # TODO: i think this can be automated
        token.generate

        unless token.save
          @error = 'Failed to save the activation token.'
          return haml :fail
        end

        @user.token = token
        unless @user.save
          @error = 'Failed to save the user with token.'
          return haml :fail
        end

        email_verification(@user)
      end

      redirect "/user/#{@user.login}"
    end

    get '/reset' do
      @done = nil
      @error = nil
      haml :reset
    end

    post '/reset' do
      @done = nil

      unless params[:email]
        @error = 'You need to specify your email.'
        return haml :reset
      end

      unless user = User.first(email: params[:email], verified: true)
        @error = 'No verified account with the address you have specified.<br>Maybe just register.'
        return haml :reset
      end

      password = ('A'..'Z').to_a.sample(12).join
      unless user.update(pass: password)
        logger.error "Couldn't set password for '#{user.login}'"
        @error = 'Sorry, something went wrong.<br>If this happens more than once contact the admin.'
        return haml :reset
      end

      email_reset(user, password)

      @done = 'You should receive an email with the new password soon.'
      @error = nil
      haml :reset
    end

    get '/verify/:login/:token' do
      unless user = User.get(params[:login])
        @error = 'No such user.'
        return haml :fail
      end

      if user.verified
        @error = 'Email already verified.'
        @error += '<br>Dangling token found, please contact the admin.' if user.token
        return haml :fail
      end

      unless user.token
        @error = 'No token found, please contact the admin.'
        return haml :fail
      end

      unless user.token.value == params[:token]
        @error = 'Wrong verification code.'
        return haml :fail
      end

      user.token.destroy || logger.error("Couldn't destroy token for '#{user.login}'")
      user.verified = true
      unless user.save
        @error = user.errors.values.join(',') + '.'
        return haml :fail
      end

      logger.info "User '#{user.login}' verified"

      redirect "/user/#{user.login}"
    end

    post '/login' do
      if @user
        @error = "You're already logged in as '#{@user.login}'."
        return haml :fail
      end

      unless params[:login] && params[:pass]
        @error = 'Missing credentials. It is either an error or you are poking.'
        return haml :fail
      end

      unless user = User.get(params[:login])
        @error = 'No such user.<br>Remember login is case-sensitive.'
        return haml :fail
      end

      unless user.valid_pass? params[:pass]
        @error = 'Access denied.'
        return haml :fail
      end

      user.seen = DateTime.now
      user.save

      session[:user] = params[:login]
      redirect @source
    end

    get '/logout' do
      session.delete(:user)
      redirect @source
    end

    get '/vote/:dir/:id' do
      unless @user
        @error = 'Not logegd in.'
        return haml :fail
      end

      unless [:up, :down].member? (dir = params[:dir].to_sym)
        @error = 'Either vote up or down, please.'
        return haml :fail
      end

      unless issue = Issue.get(params[:id])
        @error = 'No such issue.'
        return haml :fail
      end

      unless issue.open
        @error = 'The issue has been closed.'
        return haml :fail
      end

      source = "#{@source}##{issue.id}"

      if v = Vote.first(user: @user, issue: issue)
        v.dir == :up ? issue.score -= 1 : issue.score += 1
        v.destroy || logger.error("Couldn't delete vote for user '#{@user.login}' for issue '#{issue.id}'")
        issue.save || logger.error("Couldn't save issue '#{issue.id}'")

        return redirect source if v.dir == dir
      end

      vote = Vote.new(user: @user, issue: issue, dir: dir)
      vote.save || logger.error("Couldn't save vote for user '#{@user.login}' for issue '#{issue.id}'")

      dir == :up ? issue.score += 1 : issue.score -= 1
      issue.save || logger.error("Couldn't save issue '#{issue.id}'")

      redirect source
    end

    get '/user/:login' do
      unless @profile = User.get(params[:login])
        @error = 'No such user.'
        return haml :fail
      end

      query = {order: [:when.desc]}
      query[:limit] = 10 unless @user == @profile
      @votes = @profile.votes(query)
      haml :user
    end

    get '/issue/:id' do
      unless @issue = Issue.get(params[:id])
        @error = 'No such issue.'
        return haml :fail
      end

      @votes = @issue.votes(order: [:when.desc])
      @votes_up = @votes.all(dir: :up).count
      @votes_down = @votes.all(dir: :down).count
      haml :issue
    end

    get '/oauth/:service/callback' do
      case params[:service]
      when 'github'
        unless params[:code]
          logger.warn 'GitHub callback without auth code'
          return redirect :all
        end

        creds = @@oauth[:github]
        logger.debug 'GitHub POST /access_token'
        begin
          res = HTTParty.post('https://github.com/login/oauth/access_token',
                              body: {client_id: creds[:id], client_secret: creds[:secret], code: params[:code]},
                              headers: {'Accept' => 'application/json'})
        rescue RuntimeError => e
          logger.error e.to_s
          logger.debug e.backtrace.join("\n")
          @error = 'Something died, sorry.'
          return haml :fail
        end

        if res.code != 200 || !res.has_key?('access_token')
          logger.error 'GitHub callback error on POST /access_token'
          logger.debug res
          @error = "Couldn't get access token, sorry."
          return haml :fail
        end
        token = res['access_token']

        logger.debug 'GitHub GET /user'
        begin
          res = HTTParty.get('https://api.github.com/user', query: {access_token: token}, headers: {'User-Agent' => 'drbig/cddaiv'})
        rescue RuntimeError => e
          logger.error e.to_s
          logger.debug e.backtrace.join("\n")
          @error = 'Something died, sorry.'
          return haml :fail
        end

        if res.code != 200 || !res.has_key?('login')
          logger.error 'GitHub callback error on GET /user'
          logger.debug res
          @error = "Couldn't access your profile, sorry."
          return haml :fail
        end
        login = res['login']

        if res.has_key? 'email'
          email = res['email']
        else
          logger.debug 'GitHub GET /user/emails'
          begin
            res = HTTParty.get('https://api.github.com/user/emails', query: {access_token: token}, headers: {'User-Agent' => 'drbig/cddaiv'})
          rescue RuntimeError => e
            logger.error e.to_s
            logger.debug e.backtrace.join("\n")
            @error = 'Something died, sorry.'
            return haml :fail
          end

          if res.code != 200 
            logger.error 'GitHub callback error on GET /user/emails'
            logger.debug res
            @error = "You don't seem to have a public email and I couldn't get any other."
            return haml :fail
          end

          emails = res.select {|h| h['verified'] }
          unless emails.any?
            logger.error 'GitHub callback no verified email found'
            logger.debug res
            @error = "Seems you don't have any verified email anywhere."
            return haml :fail
          end

          email = emails.first['email']
        end
      when 'google'
        if params[:state] != @token
          logger.error "Google callback token mismatch: #{@token} != #{params[:state]}"
          @error = 'Security token mismatch, sorry.'
          return haml :fail
        end

        creds = @@oauth[:google]
        logger.debug 'Google POST /token'
        begin
          res = HTTParty.post('https://www.googleapis.com/oauth2/v3/token',
                              body: {client_id: creds[:id], client_secret: creds[:secret],
                              code: params[:code], redirect_uri: creds[:uri],
                              grant_type: :authorization_code},
                              headers: {'Accept' => 'application/json'})
        rescue RuntimeError => e
          logger.error e.to_s
          logger.debug e.backtrace.join("\n")
          @error = 'Something died, sorry.'
          return haml :fail
        end

        if res.code != 200 || !res.has_key?('id_token')
          logger.error 'Google callback error on POST /token'
          logger.debug res
          @error = "Couldn't get your email, sorry."
          return haml :fail
        end

        begin
          data = JWT.decode(res['id_token'], nil, false).first
        rescue JWT::DecodeError => e
          logger.error e.to_s
          logger.debug e.backtrace.join("\n")
          @error = 'Your ID token seems to be broken, sorry.'
          return haml :fail
        end

        unless data['email_verified']
          logger.error 'Google callback no verified email found'
          logger.debug data
          @error = "Seems you don't have any verified email anywhere."
          return haml :fail
        end

        login = nil
        email = data['email']
      else
        logger.warn "Unknown OAuth service '#{params[:service]}'"
        return redirect :all
      end

      # Actual webapp logic
      if user = User.first(email: email)
        if !login.nil? && user.login != login
          logger.warn "OAuth login mismatch for #{user.login}"
          @error = 'Sorry, logins mismatch...'
          return haml :fail
        end

        user.seen = DateTime.now
        user.save
      else
        login = email.split('@').first unless login

        if User.get(login)
          logger.warn "OAuth register: login '#{login}' already taken"
          @error = "Sorry, login '#{login}' has already been taken."
          return haml :fail
        end

        password = ('A'..'Z').to_a.sample(12).join
        user = User.new(login: login, pass: password, email: email, verified: true)
        user.seen = DateTime.now
        unless user.save
          @error = user.errors.values.join(',') + '.'
          return haml :fail
        end

        email_password(user, password)
      end

      session[:user] = user.login
      redirect @source
    end
  end
end
