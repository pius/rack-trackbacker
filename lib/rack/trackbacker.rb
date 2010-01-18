require 'rack/request'
require 'rack/utils'

require 'rubygems'

gem "durran-validatable", ">= 2.0.1"
require 'validatable'
require 'rdefensio'
require 'builder'

module Rack
  class Trackbacker
    attr_accessor :trackback_adder, :defensio_key, :defensio_owner_url
    
    HTTP_METHODS = %w(GET HEAD PUT POST DELETE OPTIONS)

    FORM_HEADER = "application/x-www-form-urlencoded".freeze
    TRACKBACK_HEADER = "trackback-request".freeze
    TRACKBACKABLE_ID = "trackbackable-id".freeze
    
    DEFAULT_OPTIONS = {
      :add_trackbacks_with => nil,
      :defensio_key => nil,
      :defensio_owner_url => nil
    }
    
    def initialize(app, *args)
      @app = app
      options = args.pop
      @trackback_adder = options[:add_trackbacks_with]
      options.delete![:add_trackbacks_with]
      unless @trackback_adder
        raise "Sorry, you need to provide rack-trackbacker with a lambda expression that will add the trackback to your system"
      end
      
      DEFAULT_OPTIONS.each {|name, value| send "#{name}=", value }
      options.each         {|name, value| send "#{name}=", value } if options
    end
    
    def call(env)
      req = Rack::Request.new(env)
      params = req.params.merge(:user_ip => req.ip, :defensio_key => defensio_key, :defensio_owner_url => defensio_owner_url)

      status, headers, body = @app.call(env)
      
      trackback_request = headers['Content-Type'].include?(FORM_HEADER) && headers[TRACKBACK_HEADER] && headers[TRACKBACKABLE_ID]

      if trackback_request
        trackback_successful = @trackback_adder.call[headers[TRACKBACKABLE_ID], @trackback = Trackback.new(params)]
        trackback_successful ? [201, headers, @trackback.to_xml] : [400, headers, @trackback.to_xml]
      else
        [status, headers, body]
      end
    end
  end

  class Trackback
    include Validatable

    attr_accessor :title, :excerpt, :url, :blog_name, :errors, :valid, 
     :user_ip, :article_date, :target_type,
     :additional_params, :permalink, :defensio_key, :defensio_owner_url
     
    validates_presence_of :title
    validates_presence_of :blog_name
    validates_presence_of :url

    RDefensio::API.configure do |conf|
      conf.api_key = @defensio_key
      conf.owner_url = @defensio_owner_url
      conf.format = "yaml"
      conf.service_type = "app"
    end
  
    def to_xml
      xml = Builder::XmlMarkup.new(:indent => 1)
      if valid?
        xml.instruct!
        xml.Response do
            xml.error 0
        end
      else
        xml.instruct!
        xml.Response do
            xml.error 1
            xml.message errors.join(', ')
        end
      end
    end
  
    def spammy?
      raise "Sorry, you need to provide both the defensio_key and defensio_owner_url if you want to check spamminess" unless (defensio_key && defensio_owner_url)
      @spammy ||= RDefensio::API.audit_comment({"user-ip" => user_ip,
                                    "article-date" => article_date,
                                    "comment-author" => blog_name,
                                    "comment-type" => "trackback",
                                    "comment-content" => excerpt,
                                    "comment-author-url" => url,
                                    "permalink" => permalink})
      @spammy.spam
    end
  
  end
end