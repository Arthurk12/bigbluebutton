#!/usr/bin/ruby
# Set encoding to utf-8
# encoding: utf-8

#
# Run with:
# cd /usr/local/bigbluebutton/core/scripts
# sudo -u bigbluebutton bundle exec ruby post_events/post_events_mconf_data.rb -m 31fd0bd4a609bd3adf2faa49c8abeb47bd2b9e2b-1675739800705
#

require '../../core/lib/bigbluebutton_s3'
require '../../core/lib/recordandplayback'
require 'bbbevents'
require 'dotenv'
require 'fileutils'
require 'i18n'
require 'logger'
require 'nokogiri'
require 'optimist'
require 'terminal-table'
require 'yaml'

METADATA_SHARED_ID_KEY = "mconf-shared-secret-guid"
METADATA_EXTERNAL_ID_KEY = "meetingId"
METADATA_LOCALE_KEY = "mconf-locale"
METADATA_TIMEZONE_KEY = "mconf-timezone"
METADATA_TIMEZONE_OFFSET_KEY = "mconf-timezone-offset"

def seconds_to_duration(t)
  seconds = t % 60
  minutes = (t / 60) % 60
  hours = t / (60 * 60)
  format("%02d:%02d:%02d", hours, minutes, seconds)
end

def time_to_datetime(t)
  # Convert seconds + microseconds into a fractional number of seconds
  seconds = t.sec + Rational(t.usec, 10**6)

  # Convert a UTC offset measured in minutes to one measured in a
  # fraction of a day.
  offset = Rational(t.utc_offset, 60 * 60 * 24)
  DateTime.new(t.year, t.month, t.day, t.hour, t.min, seconds, offset)
end

def local_date_time(d, timezone_offset)
  time_to_datetime(d).new_offset(timezone_offset)
end

def format_date_time(d, timezone_offset)
  local_date = local_date_time(d, timezone_offset)
  I18n.l(local_date, format: :datetime)
end

def format_time(d, timezone_offset, format: "%H:%M:%S")
  local_date = local_date_time(d, timezone_offset)
  local_date.strftime(format)
end

def format_activities(recording, target, timezone:, timezone_offset:)
  File.open(target, "w") do |file|
    file.puts I18n.t('session.name', val: recording.metadata['meetingName'])
    file.puts I18n.t('session.date', val: format_date_time(recording.start.utc, timezone_offset))
    file.puts I18n.t('session.duration', val: seconds_to_duration(recording.duration))

    unless recording.recorded_segments.empty?
      file.puts
      file.puts I18n.t('recorded_segments.title', val: recording.recorded_segments.length)
      recording.recorded_segments.each_with_index do |segment, index|
        file.puts I18n.t('recorded_segments.item', index: index + 1, start: format_time(segment.start.utc, timezone_offset), stop: format_time(segment.stop.utc, timezone_offset), duration: seconds_to_duration(segment.duration))
      end
      # sum!
      file.puts I18n.t('recorded_segments.total', val: seconds_to_duration(recording.recorded_segments.map{ |s| s.duration }.inject(0) { |sum, x| sum + x }))
    end

    unless recording.moderators.empty?
      file.puts
      file.puts I18n.t('moderators')
      recording.moderators.sort_by(&:name).uniq{ |attendee| attendee.name }.each do |attendee|
        file.puts attendee.name
      end
    end

    unless recording.viewers.empty?
      file.puts
      file.puts I18n.t('viewers')
      recording.viewers.sort_by(&:name).uniq{ |attendee| attendee.name }.each do |attendee|
        file.puts attendee.name
      end
    end

    unless recording.transfer_attendees.empty?
      file.puts
      file.puts I18n.t('transfer_attendees')
      recording.transfer_attendees.sort_by(&:name).uniq{ |attendee| attendee.name }.each do |attendee|
        file.puts attendee.name
      end
    end

    unless recording.attendees.empty?
      file.puts
      file.puts I18n.t('activity.title')
      file.puts Terminal::Table.new(
        :headings => [ I18n.t('activity.name'), I18n.t('activity.chat'), I18n.t('activity.talk'), I18n.t('activity.poll_votes'), I18n.t('activity.raisehand'), I18n.t('activity.talk_time'), I18n.t('activity.join'), I18n.t('activity.leave'), I18n.t('activity.duration') ],
        :rows => recording.attendees.sort_by(&:name).map{ |entry| [
          entry.name,
          entry.engagement[:chats],
          entry.engagement[:talks],
          entry.engagement[:poll_votes],
          entry.engagement[:raisehand],
          seconds_to_duration(entry.engagement[:talk_time]),
          format_time(entry.joined.utc, timezone_offset),
          format_time(entry.left.utc, timezone_offset),
          seconds_to_duration(entry.duration),
        ] } )
    end

    unless recording.polls.empty?
      file.puts
      file.puts I18n.t('polls.title')
      recording.polls.each_with_index do |poll, index|
        file.puts I18n.t('polls.item', index: index + 1, start: format_time(poll.start.utc, timezone_offset), votes: poll.votes.length)
        votes = []
        if poll.votes.empty?
          poll.options.each_with_index do |option, idx|
            file.puts "  #{option}"
          end
        else
          poll.options.each do |option|
            count = poll.votes.select{ |user_id, vote| vote == option}.length
            votes << {
              :count => count,
              :perc => ( ( count / poll.votes.length.to_f ) * 100 ).round(1)
            }
          end
          # sum!
          round_perc = votes.map{ |v| v[:perc].round(0) }.inject(0) { |sum, x| sum + x } == 100
          poll.options.each_with_index do |option, idx|
            file.puts "  #{option}: #{votes[idx][:count]} (#{round_perc ? votes[idx][:perc].round(0) : votes[idx][:perc]}%)"
          end
        end
      end
      file.puts Terminal::Table.new(
        :headings => [ I18n.t('polls.name') ] + (1..recording.polls.length).map { |i| "\# #{i}" },
        :rows => recording.attendees.sort_by(&:name).map{ |entry| [ entry.name ] + recording.polls.map { |poll| poll.votes[entry.ext_user_id] || "-" }
        } )
    end

    file.puts
    file.puts I18n.t('timezone', val: timezone)
  end
end

def fetch_activities(events, target_dir, timezone:, timezone_offset:)
  BigBlueButton.logger.info("Fetching users activities")

  activities = {
    :uri => "#{target_dir}/activities.txt",
    :uri_raw => "#{target_dir}/activities.json",
    :name => "Users Activities"
  }

  data = BBBEvents.parse(events)

  File.write(activities[:uri_raw], data.to_json)
  format_activities(data, activities[:uri], timezone: timezone, timezone_offset: timezone_offset)

  activities
end

def fetch_chat(events, target_dir, timezone_offset:)
  BigBlueButton.logger.info("Fetching chat")

  chat = {
    :uri => "#{target_dir}/chat.txt",
    :name => "Public Chat"
  }

  file = File.new(chat[:uri], "w")
  events.xpath("//event[@module='CHAT' and @eventname='PublicChatEvent']").each do |chat_event|
    sender_id = chat_event.xpath("senderId").text
    sender = events.at_xpath("//event[@module='PARTICIPANT' and @eventname='ParticipantJoinEvent' and ./userId/text()='#{sender_id}']/name").text
    timestampUTC = chat_event.xpath("timestampUTC").text

    message = chat_event.xpath("message").text
    message_parsed = message
    begin
      doc = Nokogiri::HTML::DocumentFragment.parse(message)
      message_parsed = doc.text
    rescue Exception => e
      # do nothing
    end

    file.puts("[#{format_time(Time.at(timestampUTC.to_i / 1000), timezone_offset, format: "%H:%M")}] #{sender}: #{message_parsed}")
  end
  file.close

  chat
end

def fetch_notes(meeting_id, events, target_dir, notes_api:)
  BigBlueButton.logger.info("Fetching notes")
  id = BigBlueButton::Events.get_notes_id(events)

  BigBlueButton.logger.info("Checking if padId=#{id} exists")

  return nil unless notes_api.pad_exists?(id)

  BigBlueButton.logger.info("padId=#{id} exists")

  notes = {
    :uri => "#{target_dir}/notes.txt",
    :name => "Shared Notes"
  }

  notes_api.export_pad(id, notes[:uri], "txt", "post_events_mconf_data")

  notes
end

def fetch_breakout_rooms_notes(events, target_dir, notes_api:)
  BigBlueButton.logger.info("Fetching breakout rooms' notes")
  ids = BigBlueButton::Events.get_breakout_rooms_notes_ids(events)
  breakout_rooms_notes = []

  ids.each_with_index do |id, index|
    next unless notes_api.pad_exists?(id)

    uri = "#{target_dir}/breakout_room_#{index + 1}_notes.txt"
    breakout_rooms_notes << {
      :uri => uri,
      :name => "Breakout room #{index + 1}'s shared notes"
    }

    notes_api.export_pad(id, uri, "txt", "post_events_mconf_data")
  end


  breakout_rooms_notes
end

def fetch_presentations(meeting_id, events, target_dir)
  BigBlueButton.logger.info("Fetching presentations")
  presentations_dir = "/var/bigbluebutton/#{meeting_id}/#{meeting_id}"
  presentations_data_dir = "#{target_dir}/presentations"
  presentations = []
  events.xpath("//event[@eventname='ConversionCompletedEvent']").each do |presentation_event|
    FileUtils.mkdir_p(presentations_data_dir) if not FileTest.directory?(presentations_data_dir)
    id = presentation_event.xpath("presentationName").text
    filename = presentation_event.xpath("originalFilename").text
    extension = filename.split('.').last
    presentation_file = "#{presentations_dir}/#{id}/#{id}.#{extension}"
    if File.exist?(presentation_file)
      FileUtils.cp(presentation_file, presentations_data_dir)
      presentations << {
        :uri => "#{presentations_data_dir}/#{id}.#{extension}",
        :name => filename
      }
    else
      BigBlueButton.logger.warn("Could not find #{presentation_file}")
    end
  end

  presentations
end

def fetch_learning_dashboard(meeting_id, events, target_dir)
  BigBlueButton.logger.info("Fetching learning dashboard")
  learning_dashboard_dir = "/var/bigbluebutton/learning-dashboard/#{meeting_id}"

  if FileTest.directory?(learning_dashboard_dir)
    # locate the json
    dir = Dir["#{learning_dashboard_dir}/*/"]
    learning_dashboard_file = "#{dir[0]}learning_dashboard_data.json"
    BigBlueButton.logger.info("File path: #{learning_dashboard_file}")
    if File.exist?(learning_dashboard_file)
      learning_dasbhoard = {
        :uri => "#{target_dir}/learning_dashboard.json",
        :name => "Learning Dashboard"
      }
      FileUtils.cp(learning_dashboard_file, learning_dasbhoard[:uri])
      learning_dasbhoard
    else
      BigBlueButton.logger.warn("Could not find #{learning_dashboard_file}")
    end
  end
end

def fetch_thumbnails(meeting_id, events, target_dir)
  BigBlueButton.logger.info("Fetching thumbnails")
  thumbnails_dir = "/var/bigbluebutton/#{meeting_id}/#{meeting_id}"
  thumbnails_data_dir = "#{target_dir}/thumbnails"
  thumbnails = []
  events.xpath("//event[@eventname='ConversionCompletedEvent']").each do |presentation_event|
    FileUtils.mkdir_p(thumbnails_data_dir) if not FileTest.directory?(thumbnails_data_dir)
    id = presentation_event.xpath("presentationName").text
    presentation_dir = "#{thumbnails_data_dir}/#{id}"
    FileUtils.mkdir_p(presentation_dir) if not FileTest.directory?(presentation_dir)
    thumbnails_folder = "/var/bigbluebutton/#{meeting_id}/#{meeting_id}/#{id}/thumbnails/"
    if FileTest.directory?(thumbnails_folder)
      FileUtils.copy_entry(thumbnails_folder, presentation_dir)
      thumbnails << {
        :uri => "#{presentation_dir}/thumbnails/",
        :name => "Presentation #{id} thumbnails",
      }
    else
      BigBlueButton.logger.warn("Could not find #{thumbnails_folder}")
    end
  end

  thumbnails
end

def fetch_svgs(meeting_id, events, target_dir)
  BigBlueButton.logger.info("Fetching svgs")
  svgs_dir = "/var/bigbluebutton/#{meeting_id}/#{meeting_id}"
  svgs_data_dir = "#{target_dir}/svgs"
  svgs = []
  events.xpath("//event[@eventname='ConversionCompletedEvent']").each do |presentation_event|
    FileUtils.mkdir_p(svgs_data_dir) if not FileTest.directory?(svgs_data_dir)
    id = presentation_event.xpath("presentationName").text
    presentation_dir = "#{svgs_data_dir}/#{id}"
    FileUtils.mkdir_p(presentation_dir) if not FileTest.directory?(presentation_dir)
    svgs_folder = "/var/bigbluebutton/#{meeting_id}/#{meeting_id}/#{id}/svgs/"
    if FileTest.directory?(svgs_folder)
      FileUtils.copy_entry(svgs_folder, presentation_dir)
      svgs << {
        :uri => "#{presentation_dir}/svgs/",
        :name => "Presentation #{id} svgs",
      }
    else
      BigBlueButton.logger.warn("Could not find #{svgs_folder}")
    end
  end

  svgs
end

def publish_to_s3(meeting_id, props, target_dir, remote_prefix)
  success = true
  props_s3 = props['s3']
  if [ "1", "true" ].include? props_s3['enabled'].to_s.downcase
    BigBlueButton.logger.info("Publishing data for #{meeting_id}")
    bucket_name = props_s3['bucket_name']
    region = props_s3['region'] || ENV['BBB_S3_REGION']
    endpoint = props_s3['endpoint'] || ENV['BBB_S3_ENDPOINT']
    key = props_s3['key'] || ENV['BBB_S3_KEY']
    secret = props_s3['secret'] || ENV['BBB_S3_SECRET']

    BigBlueButtonS3::logger = BigBlueButton.logger
    publisher = BigBlueButtonS3::Publisher.new(key: key, secret: secret, region: region, endpoint: endpoint)
    success = publisher.upload_dir(target_dir, remote_prefix, bucket_name)
    BigBlueButton.logger.info("Data published? #{success}")
  end

  success
end

begin
  opts = Optimist::options do
    opt :meeting_id, "Meeting id to process", type: :string, :required => true
  end
  meeting_id = opts[:meeting_id]

  I18n.enforce_available_locales = true
  I18n.available_locales = Dir['../../core/scripts/post_events/post_events_mconf_data_locale/*.yml'].map{ |l| File.basename(l, '.yml').to_sym }
  I18n.load_path = Dir['../../core/scripts/post_events/post_events_mconf_data_locale/*.yml']
  I18n.backend.load_translations

  bbb_props = YAML.safe_load(File.open('../../core/scripts/bigbluebutton.yml'))
  events_dir = bbb_props['events_dir']
  redis_host = bbb_props['redis_host']
  redis_port = bbb_props['redis_port']
  redis_password = bbb_props['redis_password']
  notes_endpoint = bbb_props['notes_endpoint']
  notes_apikey = bbb_props['notes_apikey']

  props = YAML::load(File.open('../../core/scripts/post_events/post_events_mconf_data.yml'))
  props_dir = props['dir']
  props_data = props['data']
  default_locale = props['default_locale'].to_sym
  default_timezone = props['default_timezone']
  default_timezone_offset = props['default_timezone_offset']

  target_dir = "#{props_dir}/#{meeting_id}"

  BigBlueButton.logger = Logger.new(STDOUT)
  BigBlueButton.redis_publisher = BigBlueButton::RedisWrapper.new(redis_host, redis_port, redis_password)

  notes_api = Etherpad::Api.new(notes_endpoint, notes_apikey)

  BigBlueButton.logger.info("Collecting data for #{meeting_id}")
  meeting_events_dir = "#{events_dir}/#{meeting_id}"
  meeting_events_xml = "#{meeting_events_dir}/events.xml"
  unless File.exists?(meeting_events_xml)
    BigBlueButton.logger.error("events.xml doesn't exist for meeting #{meeting_id}")
    FileUtils.mkdir_p(target_dir)
    exit 1
  end

  metadata = BigBlueButton::Events.get_meeting_metadata(meeting_events_xml)

  meeting_shared_id = "meeting_shared_id"
  if metadata.has_key?(METADATA_SHARED_ID_KEY) and not metadata[METADATA_SHARED_ID_KEY].to_s.empty?
    meeting_shared_id = metadata[METADATA_SHARED_ID_KEY].to_s
  else
    BigBlueButton.logger.error("Missing #{METADATA_SHARED_ID_KEY} metadata for #{meeting_id}")
    FileUtils.mkdir_p(target_dir)
    exit 1
  end

  meeting_external_id = "meeting_external_id"
  if metadata.has_key?(METADATA_EXTERNAL_ID_KEY) and not metadata[METADATA_EXTERNAL_ID_KEY].to_s.empty?
    meeting_external_id = metadata[METADATA_EXTERNAL_ID_KEY].to_s
  else
    BigBlueButton.logger.error("Missing #{METADATA_EXTERNAL_ID_KEY} metadata for #{meeting_id}")
    FileUtils.mkdir_p(target_dir)
    exit 1
  end

  locale = if metadata.has_key?(METADATA_LOCALE_KEY)
    metadata[METADATA_LOCALE_KEY].to_sym
  else
    default_locale
  end
  I18n.locale = I18n.available_locales.include?(locale) ? locale : :en

  timezone = default_timezone
  timezone_offset = default_timezone_offset
  if metadata.has_key?(METADATA_TIMEZONE_KEY) and metadata.has_key?(METADATA_TIMEZONE_OFFSET_KEY)
    timezone = metadata[METADATA_TIMEZONE_KEY].to_s
    timezone_offset = metadata[METADATA_TIMEZONE_OFFSET_KEY].to_s
  end

  # do not process breakout room
  if metadata["isBreakout"].to_s == "true"
    BigBlueButton.logger.info("Meeting #{meeting_id} is a breakout, skip it...")
    FileUtils.mkdir_p(target_dir)
    exit 0
  end

  data_path = "#{target_dir}/#{meeting_shared_id}/#{meeting_external_id}/#{meeting_id}"

  if not FileTest.directory?(target_dir)
    BigBlueButton.logger.info("Creating data path #{data_path}")
    FileUtils.mkdir_p(data_path)

    events = Nokogiri::XML(File.open(meeting_events_xml)) { |x| x.noblanks }

    notes_file = "#{meeting_events_dir}/events.etherpad"
    unless notes_api.is_pad_file_empty? notes_file
      notes_id = BigBlueButton::Events.get_notes_id(events)

      notes_api.import_pad(notes_id, notes_file, "post_events_mconf_data") unless notes_api.pad_exists?(notes_id)
    end

    data = {}
    data[:activities] = fetch_activities(meeting_events_xml, data_path, timezone: timezone, timezone_offset: timezone_offset) if props_data.include? 'activities'
    data[:chat] = fetch_chat(events, data_path, timezone_offset: timezone_offset) if props_data.include? 'chat'
    data[:notes] = fetch_notes(meeting_id, events, data_path, notes_api: notes_api) if props_data.include? 'notes'
    data[:breakout_rooms_notes] = fetch_breakout_rooms_notes(events, data_path, notes_api: notes_api) if props_data.include? 'breakout_rooms_notes'
    data[:presentations] = fetch_presentations(meeting_id, events, data_path) if props_data.include? 'presentations'
    data[:learning_dashboard] = fetch_learning_dashboard(meeting_id, events, data_path) if props_data.include? 'learning_dasbhoard'

    success = publish_to_s3(meeting_id, props, data_path, "#{meeting_shared_id}/#{meeting_external_id}/#{meeting_id}")

    BigBlueButton.redis_publisher.put_custom_message("mconf_data", meeting_id, data) if success
  else
    # retry publish to s3 if mconf-data has already been processed
    publish_to_s3(meeting_id, props, data_path, "#{meeting_shared_id}/#{meeting_external_id}/#{meeting_id}")
  end

  # publish thumbnails/svgs to a different location so we don't depend on some ids that learning-dashboard don't have access
  extra_data_path = "#{target_dir}/extra"
  if not FileTest.directory?(extra_data_path)
    BigBlueButton.logger.info("Creating extra (thumbs+svgs) data path #{extra_data_path}")
    FileUtils.mkdir_p(extra_data_path)
    events = Nokogiri::XML(File.open(meeting_events_xml)) { |x| x.noblanks }
    data = {}
    data[:thumbnails] = fetch_thumbnails(meeting_id, events, extra_data_path) if props_data.include? 'thumbnails'
    data[:svgs] = fetch_svgs(meeting_id, events, extra_data_path) if props_data.include? 'svgs'
    success = publish_to_s3(meeting_id, props, extra_data_path, "bigbluebutton/presentation/#{meeting_id}")
    BigBlueButton.redis_publisher.put_custom_message("mconf_data", meeting_id, data) if success
  else
    # retry publish to s3 if mconf-data has already been processed
    publish_to_s3(meeting_id, props, extra_data_path, "bigbluebutton/presentation/#{meeting_id}")
  end

rescue SystemExit => e
  # do nothing, just exit
rescue Exception => e
  BigBlueButton.logger.error(e.message)
  e.backtrace.each do |traceline|
    BigBlueButton.logger.error(traceline)
  end
end
