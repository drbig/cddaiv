# coding: utf-8
#

require 'dm-serializer/to_json'
require 'sinatra/base'
require 'haml'
require 'json'

require 'cddaiv/log'
require 'cddaiv/model'
require 'cddaiv/mailer'

# fix Sinatra logging retardation
class String
  def join(*_); self; end
end

module CDDAIV
  class WebApp < Sinatra::Base
    configure do
      enable :static
      enable :sessions
      enable :logging
      enable :dump_errors
      enable :raise_errors
      
      set :root, File.join(File.dirname(__FILE__), '..', '..')
      set :public_dir, File.join(settings.root, 'static')
      set :views, File.join(settings.root, 'templates')
      set :session_secret, 'whatever for now'
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
    end

    before do
      env['rack.logger'] = CDDAIV::Log.logger
      env['rack.errors'] = CDDAIV::Log.logger
      @user = session[:user] ? User.get(session[:user]) : nil
      @source = params[:source]
    end

    get '/' do
      redirect :all
    end

    get '/all' do
      @issues = Issue.all(open: true, order: [:from.desc])
      @votes = @issues.map {|i| @user.votes(issue: i).first } if @user
      haml :all
    end

    get '/top' do
      @issues = Issue.all(open: true, limit: 30, order: [:score.desc]).to_a
      @votes = @issues.map {|i| @user.votes(issue: i).first } if @user
      haml :top
    end

    get '/bottom' do
      @issues = Issue.all(open: true, limit: 30, order: [:score.asc]).to_a
      @votes = @issues.map {|i| @user.votes(issue: i).first } if @user
      haml :bottom
    end

    get '/closed' do
      @issues = Issue.all(open: false, order: [:until.desc]).to_a
      haml :closed
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

      if User.get(params[:login])
        @error = "Sorry, login '#{params[:login]}' is already taken."
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
      # have to do it manually, 'cause dm is retarted
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

      if params[:email]
        @user.email = params[:email] 
        @user.verified = false
      end

      unless @user.save
        @error = @user.errors.values.join(',') + '.'
        return haml :fail
      end

      if params[:email]
        @user.token.destroy if @user.token

        token = Token.new(user: @user)
        # have to do it manually, 'cause dm is retarted
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

        email_verification(user)
      end

      redirect "/user/#{@user.login}"
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
        @error = 'Access denied.'
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
      redirect '/all'
    end

    get '/vote/:dir/:id/:source' do
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

      if v = Vote.first(user: @user, issue: issue)
        v.dir == :up ? issue.score -= 1 : issue.score += 1
        v.destroy || logger.error("Couldn't delete vote for user '#{@user.login}' for issue '#{issue.id}'")
        issue.save || logger.error("Couldn't save issue '#{issue.id}'")

        return redirect params[:source] if v.dir == dir
      end

      vote = Vote.new(user: @user, issue: issue, dir: dir)
      vote.save || logger.error("Couldn't save vote for user '#{@user.login}' for issue '#{issue.id}'")

      dir == :up ? issue.score += 1 : issue.score -= 1
      issue.save || logger.error("Couldn't save issue '#{issue.id}'")

      redirect @source
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
        return render haml :fail
      end

      @votes = @issue.votes(order: [:when.desc])
      @votes_up = @votes.all(dir: :up).count
      @votes_down = @votes.all(dir: :down).count
      haml :issue
    end
  end
end
