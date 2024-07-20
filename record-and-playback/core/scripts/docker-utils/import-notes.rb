require 'digest'
require 'json'
require 'logger'
require 'net/http'
require 'nokogiri'
require 'optimist'
require 'retriable'
require 'ruby-limiter'
require 'uri'
require 'yaml'

#
# Run with:
# cd /var/bigbluebutton
# docker run --rm -it --network host -v $(pwd)/events:/var/bigbluebutton/events:ro -v /usr/local/bigbluebutton/core/scripts/bigbluebutton.yml:/usr/local/bigbluebutton/core/scripts/bigbluebutton.yml mconf/mconf-rec-worker:dev bundle exec ruby docker-utils/import-notes.rb
#

MAX_ATTEMPTS = 10
MAX_ELAPSED_TIME = 60

opts = Optimist::options do
  opt :meeting_id, "Record ID", :type => :string
  opt :overwrite, "Overwrite notes if already exists", :type => :flag, :default => false
end

bbb_props = YAML::load(File.open('/usr/local/bigbluebutton/core/scripts/bigbluebutton.yml'))

logger = Logger.new(STDOUT)
events_dir = bbb_props['events_dir']
endpoint = bbb_props['notes_endpoint']
api_key = bbb_props['notes_apikey']

import_limiter = Limiter::RateQueue.new(6, interval: 90)

$print_retry = Proc.new do |exception, try, elapsed_time, next_interval|
  msg = "Attempt #{try} failed due to #{exception.class}: '#{exception.message}'"
  msg += " - trying again in #{next_interval.round(1)} seconds" unless next_interval.nil?
  logger.warn msg
end

uri = URI.parse(endpoint)
$http = Net::HTTP.new(uri.host, uri.port)

def retriable_request(request)
  response = nil
  Retriable.retriable(tries: MAX_ATTEMPTS, on_retry: $print_retry, max_elapsed_time: MAX_ELAPSED_TIME) do
    response = $http.request(request)
    raise "Response to #{request.method} #{request.path} was #{response.code} - #{response.msg}" unless response.kind_of? Net::HTTPSuccess
  end
  response
end

def get_notes_id(events)
  notes_id = 'undefined'
  cc_token = '_cc_'
  events.xpath("/recording/event[@eventname='AddPadEvent']").each do |pad_event|
    pad_id = pad_event.at_xpath('padId').text
    notes_id = pad_id unless pad_id.include? cc_token
  end
  notes_id
end

logger.info "Requesting API version"
request_uri = "/api"
request = Net::HTTP::Get.new(request_uri)
response = retriable_request(request)
api_version = JSON.parse(response.body)["currentVersion"]

files = opts[:meeting_id].nil? ? Dir.glob("#{events_dir}/*/events.etherpad") : [ "#{events_dir}/#{opts[:meeting_id]}/events.etherpad" ]

files.each do |file|
  unless File.exists? file
    logger.info "#{file} doesn't exist, skip it"
    next
  end

  record_id = File.basename(File.dirname(file))

  file_content = File.read(file)
  content = nil
  begin
    content = JSON.parse(file_content)
  rescue JSON::ParserError => e
    logger.error "File content for #{record_id} isn't valid"
    next
  end

  is_empty = content.values.dig(0, "atext", "text").strip.empty?

  if is_empty
    logger.info "Pad for #{record_id} is empty, skip it"
    next
  end

  events_xml = "#{events_dir}/#{record_id}/events.xml"
  doc = Nokogiri::XML(File.open(events_xml)) { |x| x.noblanks }
  pad = get_notes_id(doc)
  pad = Digest::SHA1.hexdigest(record_id + api_key) if pad == 'undefined'

  logger.info "Checking if pad #{pad} exists"
  request_uri = "/api/#{api_version}/getRevisionsCount?apikey=#{api_key}&padID=#{pad}"

  request = Net::HTTP::Get.new(request_uri)
  response = retriable_request(request)
  body = JSON.parse(response.body)
  already_exists = body["message"] == "ok"

  if already_exists
    if opts[:overwrite]
      logger.info "Deleting existing pad #{pad}"
      request_uri = "/api/#{api_version}/deletePad?apikey=#{api_key}&padID=#{pad}"
      request = Net::HTTP::Get.new(request_uri)
      response = retriable_request(request)
      body = JSON.parse(response.body)
      unless body["message"] == "ok"
        logger.info "Couldn't delete pad to import #{record_id}: #{body["message"]}"
        next
      end
    else
      logger.info "Pad for #{record_id} already exists on Etherpad, skip it"
      next
    end
  end

  logger.info "Creating pad #{pad}"
  request_uri = "/api/#{api_version}/createPad?apikey=#{api_key}&padID=#{pad}"
  request = Net::HTTP::Get.new(request_uri)
  response = retriable_request(request)
  body = JSON.parse(response.body)
  unless body["message"] == "ok"
    logger.info "Couldn't create pad to import #{record_id}: #{body["message"]}"
    next
  end

  logger.info "Importing pad #{pad}"
  request_uri = "#{uri.request_uri}/#{pad}/import"
  request = Net::HTTP::Post.new(request_uri)
  request.set_form [['file', File.read(file), {filename: "#{record_id}.etherpad"}]], 'multipart/form-data'
  import_limiter.shift
  response = retriable_request(request)
  # doesn't return a JSON, rely on http code
  logger.info "Pad for #{record_id} successfully imported"
end

exit 0
