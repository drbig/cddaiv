# coding: utf-8
#

require 'dm-serializer/to_json'
require 'sinatra/base'
require 'haml'
require 'json'

require 'cddaiv/log'
require 'cddaiv/model'

# fix Sinatra logging retardation
class String
  def join; self; end
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
      haml :closed
    end

    get '/bottom' do
      @issues = Issue.all(open: true, limit: 30, order: [:score.asc]).to_a
      haml :closed
    end

    get '/closed' do
      @issues = Issue.all(open: false, limit: 30, order: [:from.desc]).to_a
      haml :closed
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

      user = User.get(params[:login])
      unless user
        @error = 'Access denied.'
        return haml :fail
      end

      unless user.valid_pass? params[:pass]
        @error = 'Access denied.'
        return haml :fail
      end

      session[:user] = params[:login]
      if params[:source]
        redirect params[:source]
      else
        @error = 'No source. It is either an error or you are poking.'
        return haml :fail
      end
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

      if v = Vote.first(user: @user, issue: issue)
        v.dir == :up ? issue.score -= 1 : issue.score += 1
        v.destroy!
        issue.save!
        
        return redirect params[:source] if v.dir == dir
      end

      vote = Vote.new(user: @user, issue: issue, dir: dir)
      vote.save!

      dir == :up ? issue.score += 1 : issue.score -= 1
      issue.save!

      redirect params[:source]
    end
  end
end
