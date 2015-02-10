# coding: utf-8
#

require 'sinatra/base'
require 'haml'

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
      haml :new_issues
    end
  end
end
