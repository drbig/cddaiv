# coding: utf-8
#

require 'dm-serializer/to_json'
require 'sinatra/base'
require 'haml'
require 'json'

require 'cddaiv/log'
require 'cddaiv/model'

module CDDAIV
  class WebApp < Sinatra::Base
    configure do
      enable :static
      enable :sessions
      enable :logging
      
      set :root, File.join(File.dirname(__FILE__), '..', '..')
      set :public_dir, File.join(settings.root, 'static')
      set :views, File.join(settings.root, 'templates')
      set :session_secret, 'whatever for now'
      set :haml, ugly: true
    end

    before do
      env['rack.logger'] = CDDAIV::Log.logger
      env['rack.errors'] = CDDAIV::Log.logger
    end

    get '/' do
      haml :index
    end

    get '/vote/:dir/:id' do
      content_type 'application/json'
      return {error: 'Not logged in.'}.to_json unless session[:user]
      return {error: 'Either vote up or down, please.'}.to_json unless [:up, :down].member? (dir = params[:dir].to_sym)

      user = User.get(session[:user])
      issue = Issue.get(params[:id])
      return {error: 'No such issue.'}.to_json unless issue
    end

    get '/issues/:op' do
      op = params[:op].to_sym
      data = case op
             when :all
               Issue.all(open: true, order: [:from.desc]).to_a
             when :closed
               Issue.all(open: false, limit: 30, order: [:from.desc]).to_a
             when :top
               Issue.all(open: true).sort_by {|i| i.votes.count  }.to_a.slice(0, 30)
             when :bottom
               Issue.all(open: true).sort_by {|i| -i.votes.count }.to_a.slice(0, 30)
             when :user
               if session[:user]
                 User.get(session[:user]).votes.map(&:issue).sort_by {|i| i.votes.count }.to_a
               else
                 {error: 'Not logged in.'}
               end
             else
               {error: 'Unknown data op.'}
             end

      content_type 'application/json'
      data.to_json
    end

    post '/user/login' do
      content_type 'application/json'

      return {error: 'Already logged in.'}.to_json    if session[:user]
      return {error: 'Missing credentials.'}.to_json  unless params[:login] && params[:pass]
      return {error: 'Access denied.'}.to_json        unless user = User.get(params[:login])
      return {error: 'Access denied.'}.to_json        unless user.valid_pass? params[:pass]

      session[:user] = params[:login]
      {success: 'Logged in.'}.to_json
    end

    post '/user/add' do
    end
  end
end
