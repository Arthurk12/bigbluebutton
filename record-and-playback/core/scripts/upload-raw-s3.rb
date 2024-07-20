# Set encoding to utf-8
# encoding: UTF-8

require '../lib/recordandplayback'
require '../lib/bigbluebutton_s3'
require 'logger'
require 'optimist'
require 'yaml'

bbb_props = YAML::load(File.open('bigbluebutton.yml'))
log_dir = bbb_props['log_dir']
recording_dir = bbb_props['recording_dir']

props = YAML::load(File.open('upload-raw-s3.yml'))

opts = Optimist::options do
  opt :meeting_id, "RecordID to upload", :type => String, :required => true
  opt :log_stdout, "Log to STDOUT", :type => :flag
end
meeting_id = opts[:meeting_id]

logger = opts[:log_stdout] ? Logger.new(STDOUT) : Logger.new("#{log_dir}/upload-raw-s3.log", 'daily')
BigBlueButton.logger = logger

# get meeting duration and pass as metadata to s3
events_xml = "#{recording_dir}/raw/#{meeting_id}/events.xml"
if ! File.exists?(events_xml)
  logger.error "No events.xml found for #{meeting_id}"
  exit 0
end

doc = Nokogiri::XML(File.open(events_xml)) { |x| x.noblanks }

if ! BigBlueButton::Events.has_events?(doc)
  logger.error "Empty events.xml found for #{meeting_id}"
  exit 0
end

duration = BigBlueButton::Events.get_recording_length(doc)
if duration == 0
  duration = BigBlueButton::Events.last_event_timestamp(doc) - BigBlueButton::Events.first_event_timestamp(doc)
end

upload_config_selector = props['config_selector']
# select first match for xpath
upload_config = upload_config_selector.detect{ |entry| ! doc.at_xpath(entry['xpath']).nil? }
if upload_config.nil?
  logger.info "No valid config found to upload #{meeting_id}"
  exit 0
end

logger.info "Valid config file for upload named #{upload_config['name']}"
key = upload_config['bbb_s3_key'] || ""
secret = upload_config['bbb_s3_secret'] || ""
endpoint = upload_config['bbb_s3_endpoint'] || ""
region = upload_config['bbb_s3_region'] || ""
bucket = upload_config['bbb_s3_bucket'] || ""

BigBlueButtonS3::logger = logger
publisher = BigBlueButtonS3::Publisher.new(key: key, secret: secret, region: region, endpoint: endpoint)
success = publisher.upload_raw(meeting_id, bucket, combine: true, duration: duration)
logger.info "Success? #{success}"
