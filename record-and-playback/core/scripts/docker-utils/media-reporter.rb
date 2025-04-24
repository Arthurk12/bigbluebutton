require 'elasticsearch'
require 'json'
require 'yaml'
require 'nokogiri'

require File.expand_path('../../../lib/recordandplayback', __FILE__)

class MediaReporter
  def initialize
    @logger = BigBlueButton.logger
  end

  def logger=(logger)
    @logger = logger
  end

  # Helper function to format duration in milliseconds to a human-readable format
  def self.format_duration(milliseconds)
    total_seconds = milliseconds / 1000
    minutes = total_seconds / 60
    seconds = total_seconds % 60
    "#{minutes}m#{seconds}s"
  end

  def self.format_timestamp_s(value)
    Time.at(value).utc.strftime("%Y-%m-%dT%H:%M:%S.%3N%z")
  end

  def self.format_timestamp_ms(value)
    self.format_timestamp_ms(value / 1000)
  end

  def perform(record_id)
    props = YAML::load(File.open('bigbluebutton.yml'))
    recording_dir = props['recording_dir']
    playback_protocol = props['playback_protocol']
    playback_host = props['playback_host']
    raw_dir = "#{recording_dir}/raw/#{record_id}"

    media = {}

    Dir.glob( [ "#{raw_dir}/audio/**/*.webm",
                "#{raw_dir}/deskshare/**/*.webm",
                "#{raw_dir}/video/**/*.webm" ]).each do |filename|

      obj = {}
      obj[:mediaFileExists] = true
      # type is audio, video or deskshare
      obj[:type] = filename.split('/')[6]
      obj[:filePath] = filename
      key = File.basename(filename, ".webm")

      stats_file = "#{File.dirname(filename)}/#{key}-stats.json"
      if obj[:statsFileExists] = File.exist?(stats_file)
        obj.merge!(File.open(stats_file) { |file| JSON.parse(file.read, :symbolize_names => true) })
      end

      # convert captureStats.tracks into an array, which will be better suitable for elasticsearch
      if obj[:captureStats][:tracks].is_a?(Hash)
        obj[:captureStats][:tracks] = obj[:captureStats][:tracks].values
      end

      media[key] = obj
    end

    events_xml_filename = "#{recording_dir}/raw/#{record_id}/events.xml"
    if File.exist?(events_xml_filename)
      events_xml = Nokogiri::XML(File.open(events_xml_filename)) { |x| x.noblanks }
      talking_events = BigBlueButton::Events.get_talking_events(events_xml)

      first_node = events_xml.xpath("/recording/event[1]").first
      firstTimestamp_utc = first_node.at_xpath("timestampUTC").text.to_i
      firstTimestamp = first_node.at_xpath("@timestamp").text.to_i

      recording_events = BigBlueButton::Events.match_start_and_stop_rec_events(BigBlueButton::Events.get_start_and_stop_rec_events(events_xml))

      media.each do |key, record|
        case record[:type]
        when "audio"
          media[key][:publishedEventCount] = events_xml.xpath("recording/event[@module='bbb-webrtc-sfu' and @eventname='AudioTrackPublishedEvent' and contains(./filename, '#{key}') ]").length
          media[key][:unpublishedEventCount] = events_xml.xpath("recording/event[@module='bbb-webrtc-sfu' and @eventname='AudioTrackUnpublishedEvent' and contains(./filename, '#{key}') ]").length
        when "video"
          media[key][:publishedEventCount] = events_xml.xpath("recording/event[@module='bbb-webrtc-sfu' and @eventname='StartWebRTCShareEvent' and contains(./filename, '#{key}') ]").length
          media[key][:unpublishedEventCount] = events_xml.xpath("recording/event[@module='bbb-webrtc-sfu' and @eventname='StopWebRTCShareEvent' and contains(./filename, '#{key}') ]").length
        when "deskshare"
          media[key][:publishedEventCount] = events_xml.xpath("recording/event[@module='bbb-webrtc-sfu' and @eventname='StartWebRTCDesktopShareEvent' and contains(./filename, '#{key}') ]").length
          media[key][:unpublishedEventCount] = events_xml.xpath("recording/event[@module='bbb-webrtc-sfu' and @eventname='StopWebRTCDesktopShareEvent' and contains(./filename, '#{key}') ]").length
        end
      end

      events_xml.xpath(
        "recording/event[@module='bbb-webrtc-sfu' and @eventname='AudioTrackPublishedEvent' and ./source='microphone']" +
        "| recording/event[@module='bbb-webrtc-sfu' and @eventname='StartWebRTCShareEvent']" +
        "| recording/event[@module='bbb-webrtc-sfu' and @eventname='StartWebRTCDesktopShareEvent']"
      ).each do |event|
        event_name = event.at_xpath('@eventname')&.text
        stop_event_name = case event_name
          when 'StartWebRTCShareEvent'
            'StopWebRTCShareEvent'
          when 'StartWebRTCDesktopShareEvent'
            'StopWebRTCDesktopShareEvent'
          when 'AudioTrackPublishedEvent'
            'AudioTrackUnpublishedEvent'
          end

        filename = event.at_xpath('filename')&.text
        if filename.nil?
          BigBlueButton.logger.warn "#{event_name} has no filename."
          next
        end

        key = File.basename(filename, ".webm")
        record = media[key] || { :mediaFileExists => false }

        if record[:eventProcessed]
          BigBlueButton.logger.warn "#{event_name} already processed for this file."
          next
        end

        record[:eventProcessed] = true
        userId = event.at_xpath('userId')&.text
        if userId.nil?
          BigBlueButton.logger.warn "#{event_name} has no userId."
        else
          join_event = events_xml.xpath("recording/event[@module='PARTICIPANT' and @eventname='ParticipantJoinEvent' and ./userId='#{userId}']").first
          user = {
            :userId => userId,
            :externalUserId => join_event.at_xpath('externalUserId')&.text,
            :name => join_event.at_xpath('name')&.text,
            :role => join_event.at_xpath('role')&.text,
          }
          record[:user] = user
        end

        record[:record] = {
          :startTimestamp => event.at_xpath('@timestamp')&.text.to_i,
        }

        file_path = Dir.glob("#{raw_dir}/**/#{File.basename(filename)}").first
        if record[:mediaFileExists]
          duration = nil
          if record[:type] == "audio"
            duration = BigBlueButton::EDL::Audio.audio_info(file_path)&.dig(:duration)
          else
            duration = BigBlueButton::EDL::Video.video_info(file_path)&.dig(:duration)
          end
          record.merge!({
            :file => {
              :duration => duration
            }
          })
        end

        unpublished_event = events_xml.xpath("recording/event[@module='bbb-webrtc-sfu' and @eventname='#{stop_event_name}' and ./filename='#{filename}' ]").first
        if unpublished_event.nil?
          BigBlueButton.logger.warn "#{event_name} has no corresponding #{stop_event_name}."
        else
          record[:record][:endTimestamp] = unpublished_event.at_xpath('@timestamp')&.text.to_i
          record[:record][:duration] = record[:record][:endTimestamp] - record[:record][:startTimestamp]

          recording_duration_past = 0
          recording_events.each_with_index do |recording_event, idx|
            recorded_file = BigBlueButton.find_intersection( [ [ record[:record][:startTimestamp], record[:record][:endTimestamp] ] ], [ [ recording_event[:start_timestamp], recording_event[:stop_timestamp] ] ])

            if recorded_file.empty?
              recording_duration_past += recording_event[:stop_timestamp] - recording_event[:start_timestamp]
            else
              recording_invisible = 0
              if record[:record][:startTimestamp] > recording_event[:start_timestamp]
                recording_duration_past += record[:record][:startTimestamp] - recording_event[:start_timestamp]
              else
                recording_invisible = recording_event[:start_timestamp] - record[:record][:startTimestamp]
              end
              record[:record][:recordedSegment] = idx
              record[:record][:recordedTimestamp] = recording_duration_past
              record[:record][:recordedLink] = "#{playback_protocol}://#{playback_host}/playback/presentation/2.3/#{record_id}?t=#{MediaReporter.format_duration(recording_duration_past)}"
              record[:record][:recordedInvisible] = recording_invisible
              break
            end
          end

          if record[:type] == "audio"
            talking_events_considered = BigBlueButton.find_intersection([[record[:record][:startTimestamp], record[:record][:endTimestamp]]], talking_events.dig(userId, :events)&.map { |e| [e[:start], e[:stop]] }).map{ |e| { :start => e[0], :stop => e[1] } }
            if talking_events_considered.empty?
              record[:talking] = {
                :duration => 0,
                :eventsCount => 0,
              }
            else
              record[:talking] = {
                :firstTimestamp => talking_events_considered.first[:start],
                :lastTimestamp => talking_events_considered.last[:stop],
                :duration => talking_events_considered.sum { |e| e[:stop] - e[:start] },
                :eventsCount => talking_events_considered.length
              }
              record[:talking][:silenceAtBeginning] = record[:talking][:firstTimestamp] - record[:record][:startTimestamp]
              record[:talking][:silenceAtEnd] = record[:record][:endTimestamp] - record[:talking][:lastTimestamp]
            end

            if ! record.dig(:file, :duration).nil?
              silence_events = BigBlueButton::EDL::Audio.get_silence(file_path)
              noise_events_considered = BigBlueButton.subtract_periods([[0, record[:file][:duration]]], silence_events.map { |e| [e[:start], e[:end]] }).map{ |e| { :start => e[0] + record[:record][:startTimestamp], :stop => e[1] + record[:record][:startTimestamp] } }

              if noise_events_considered.empty?
                record[:noise] = {
                  :duration => 0,
                  :eventsCount => 0,
                }
              else
                record[:noise] = {
                  :firstTimestamp => noise_events_considered.first[:start],
                  :lastTimestamp => noise_events_considered.last[:stop],
                  :duration => noise_events_considered.sum { |e| e[:stop] - e[:start] },
                  :eventsCount => noise_events_considered.length,
                }
                record[:noise][:silenceAtBeginning] = record[:noise][:firstTimestamp] - record[:record][:startTimestamp]
                record[:noise][:silenceAtEnd] = record[:record][:endTimestamp] - record[:noise][:lastTimestamp]

                if record[:talking][:eventsCount] > 0
                  intersect_talking_noise = BigBlueButton.find_intersection(talking_events_considered.map { |e| [e[:start], e[:stop]] }, noise_events_considered.map { |e| [e[:start], e[:stop]] }).map{ |e| { :start => e[0], :stop => e[1] } }
                  record[:talkingNoiseDuration] = intersect_talking_noise.sum { |e| e[:stop] - e[:start] }
                  record[:talkingNoiseRatio] = ( record[:talkingNoiseDuration] / record[:talking][:duration].to_f ).round(3)
                end
              end
            end
          end
        end

        record[:noise][:firstTimestamp] += firstTimestamp_utc - firstTimestamp if record.dig(:noise, :firstTimestamp)
        record[:noise][:lastTimestamp] += firstTimestamp_utc - firstTimestamp if record.dig(:noise, :lastTimestamp)
        record[:talking][:firstTimestamp] += firstTimestamp_utc - firstTimestamp if record.dig(:talking, :firstTimestamp)
        record[:talking][:lastTimestamp] += firstTimestamp_utc - firstTimestamp if record.dig(:talking, :lastTimestamp)
        record[:record][:startTimestamp] += firstTimestamp_utc - firstTimestamp if record.dig(:record, :startTimestamp)
        record[:record][:endTimestamp] += firstTimestamp_utc - firstTimestamp if record.dig(:record, :endTimestamp)

        media[key] = record
      end
    end

    elastic_client = nil
    begin
      elastic_client = Elasticsearch::Client.new hosts: [
        { host: ENV['MCONF_REC_NOTIFIER_ELASTIC_HOST'],
          path: String.new(ENV['MCONF_REC_NOTIFIER_ELASTIC_PATH']),
          port: ENV['MCONF_REC_NOTIFIER_ELASTIC_PORT'],
          user: ENV['MCONF_REC_NOTIFIER_ELASTIC_AUTH_USER'],
          password: ENV['MCONF_REC_NOTIFIER_ELASTIC_AUTH_PASS'],
          scheme: ENV['MCONF_REC_NOTIFIER_ELASTIC_SCHEME'] }
      ], log: true, retry_on_failure: 20, request_timeout: 30
    rescue
      BigBlueButton.logger.warn "Failed to connect to Elasticsearch: #{$!}"
    end

    if elastic_client.nil?
      puts JSON.pretty_generate(media)
    else
      body = []
      timestamp = BigBlueButton.record_id_to_timestamp(record_id)
      index_suffix = Time.at(timestamp).utc.strftime(ENV['MCONF_REC_NOTIFIER_ELASTIC_MEDIA_STATS_INDEX_SUFFIX'])
      index = "#{ENV['MCONF_REC_NOTIFIER_ELASTIC_MEDIA_STATS_INDEX']}-#{index_suffix}"

      media.each do |key, record|
        record[:timestamp] = MediaReporter.format_timestamp_s(timestamp)

        body << {
          index: {
            _index: index,
            _id: record.dig(:captureStats, :recorderSessionId) || SecureRandom.uuid
          }
        }
        body << record
      end
      elastic_client.bulk(body: body) if ! body.empty?
    end
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.length > 0
    record_id = ARGV[0]
    MediaReporter.new.perform(record_id)
  end
end
