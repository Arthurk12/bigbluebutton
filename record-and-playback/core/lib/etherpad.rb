# Set encoding to utf-8
# encoding: UTF-8

require 'json'
require 'logger'
require 'net/http'
require 'retriable'
require 'uri'

module Etherpad
  MAX_ATTEMPTS = 10
  MAX_ELAPSED_TIME = 60

  def self.print_retry
    return @print_retry if @print_retry

    @print_retry = Proc.new do |exception, try, elapsed_time, next_interval|
      msg = "Attempt #{try} failed due to #{exception.class}: '#{exception.message}'"
      msg += " - trying again in #{next_interval.round(1)} seconds" unless next_interval.nil?
      self.logger.warn msg
    end
  end

  def self.retriable_request(http, request)
    response = nil
    Retriable.retriable(tries: MAX_ATTEMPTS, on_retry: self.print_retry, max_elapsed_time: MAX_ELAPSED_TIME) do
      response = http.request(request)
      raise "Response to #{request.method} #{request.path} was #{response.code} - #{response.msg}" unless response.kind_of? Net::HTTPSuccess
    end
    response
  end

  # Logs information about its progress.
  # Replace with your own logger if you desire.
  #
  # @param [Logger] log your own logger
  # @return [Logger] the logger you set
  def self.logger=(log)
    @logger = log
  end

  # Get logger.
  #
  # @return [Logger]
  def self.logger
    return @logger if @logger
    logger = Logger.new(STDOUT)
    logger.level = Logger::INFO
    @logger = logger
  end

  class Api
    def initialize(endpoint, api_key)
      @api_key = api_key

      @uri = URI.parse(endpoint)
      @http = Net::HTTP.new(@uri.host, @uri.port)

      request_uri = "/api"
      request = Net::HTTP::Get.new(request_uri)
      response = Etherpad.retriable_request(@http, request)
      @api_version = JSON.parse(response.body)["currentVersion"]
    end

    def pad_exists?(pad)
      request_uri = "/api/#{@api_version}/getRevisionsCount?apikey=#{@api_key}&padID=#{pad}"

      request = Net::HTTP::Get.new(request_uri)
      response = Etherpad.retriable_request(@http, request)
      body = JSON.parse(response.body)
      body["message"] == "ok"
    end

    def delete_pad(pad)
      request_uri = "/api/#{@api_version}/deletePad?apikey=#{@api_key}&padID=#{pad}"
      request = Net::HTTP::Get.new(request_uri)
      response = Etherpad.retriable_request(@http, request)
      body = JSON.parse(response.body)
      body["message"] == "ok"
    end

    def create_pad(pad)
      request_uri = "/api/#{@api_version}/createPad?apikey=#{@api_key}&padID=#{pad}"
      request = Net::HTTP::Get.new(request_uri)
      response = Etherpad.retriable_request(@http, request)
      body = JSON.parse(response.body)
      body["message"] == "ok"
    end

    def create_group_pad(pad)
      group_id, pad_name = parse_pad_id(pad)

      request_uri = "/api/#{@api_version}/createGroupPad?apikey=#{@api_key}&groupID=#{group_id}&padName=#{pad_name}"
      request = Net::HTTP::Get.new(request_uri)
      response = Etherpad.retriable_request(@http, request)
      body = JSON.parse(response.body)
      body["message"] == "ok"
    end

    def import_pad(pad, file, author_name)
      author_id = create_author(pad, author_name)
      session_id = create_session(pad, author_id)
      create_group_pad(pad)

      request_uri = File.join([ @uri.request_uri, "/p/#{pad}/import" ].reject{ |s| s == "/" })

      request = Net::HTTP::Post.new(request_uri)
      request["Cookie"] = "sessionID=#{session_id}"
      request.set_form [['file', File.read(file), {filename: "#{pad}.etherpad"}]], 'multipart/form-data'
      response = Etherpad.retriable_request(@http, request)
      true
    end

    def export_pad(pad, file, format, author_name)
      author_id = create_author(pad, author_name)
      session_id = create_session(pad, author_id)

      request_uri = File.join([ @uri.request_uri, "/p/#{pad}/export/#{format}" ].reject{ |s| s == "/" })

      request = Net::HTTP::Get.new(request_uri)
      request["Cookie"] = "sessionID=#{session_id}"

      begin
        @http.request request do |response|
          open file, 'w' do |io|
            response.read_body do |chunk|
              io.write chunk
            end
          end
        end
      rescue Exception => e
        BigBlueButton.logger.error "Failed to export pad #{pad} as #{format}: #{e.to_s}"
        FileUtils.rm_f file
      end

      true
    end

    def is_pad_file_empty?(file)
      return true unless File.exists? file

      file_content = File.read(file)
      is_empty = true
      begin
        content = JSON.parse(file_content)
        is_empty = content.values.dig(0, "atext", "text").strip.empty?
      rescue JSON::ParserError

      end
      is_empty
    end

    private

    def parse_pad_id(pad)
      group_id, pad_name = pad.split("$")
      [ group_id, pad_name ]
    end

    def create_author(pad, author_name)
      group_id, _ = parse_pad_id(pad)
      request_uri = "/api/#{@api_version}/createAuthor?apikey=#{@api_key}&name=#{author_name}"

      request = Net::HTTP::Get.new(request_uri)
      response = Etherpad.retriable_request(@http, request)
      body = JSON.parse(response.body)
      raise "Cannot create author #{author_name} for pad #{pad}" unless body["message"] == "ok"
      body["data"]["authorID"]
    end

    def create_session(pad, author_id)
      group_id, _ = parse_pad_id(pad)
      request_uri = "/api/#{@api_version}/createSession?apikey=#{@api_key}&groupID=#{group_id}&authorID=#{author_id}&validUntil=#{(Time.now.to_f * 1000).to_i + 60000}"

      request = Net::HTTP::Get.new(request_uri)
      response = Etherpad.retriable_request(@http, request)
      body = JSON.parse(response.body)
      raise "Cannot create session for pad #{pad}" unless body["message"] == "ok"
      body["data"]["sessionID"]
    end
  end
end
