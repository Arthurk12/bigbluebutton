#!/usr/bin/env ruby
# frozen_string_literal: true

# This file is part of BigBlueButton.
#
# Copyright © BigBlueButton Inc. and by respective authors.
#
# BigBlueButton is free software: you can redistribute it and/or modify it
# under the terms of the GNU Lesser General Public License as published by the
# Free Software Foundation, either version 3.0 of the License, or (at your
# option) any later version.
#
# BigBlueButton is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for more
# details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with BigBlueButton. If not, see <https://www.gnu.org/licenses>.

require File.expand_path('../../lib/recordandplayback', __dir__)
require File.expand_path('../../lib/recordandplayback/edl', __dir__)
require 'active_support/core_ext/hash'
require 'optimist'
require 'yaml'
require 'nokogiri'
require 'erb'
require 'cgi'
require 'i18n'
require 'securerandom'

LANGUAGE_MAP = {
  "en" => "eng",  # English
  "fr" => "fra",  # French
  "pt" => "por",  # Portuguese
  "es" => "spa",  # Spanish
  "de" => "deu",  # German
  "it" => "ita",  # Italian
  "ru" => "rus",  # Russian
  "ja" => "jpn",  # Japanese
  "ko" => "kor",  # Korean
  "zh" => "zho",  # Chinese (sometimes 'chi' also used, but 'zho' is standard)
  "ar" => "ara",  # Arabic
}

opts = Optimist.options do
  opt :meeting_id, 'Meeting id to process', type: String
  opt :log_stdout, "Log to STDOUT", :type => :flag
  opt :stderr, 'Log output to stderr'
end
Optimist.die :meeting_id, 'must be provided' unless opts[:meeting_id]
meeting_id = opts[:meeting_id]

start_real_time = nil
begin
  m = /-(\d+)$/.match(meeting_id)
  start_real_time = m[1].to_i
end

# Load parameters and set up paths
props = YAML.safe_load(File.open(File.expand_path('../bigbluebutton.yml', __dir__)))
video_props = YAML.safe_load(File.open(File.expand_path('../video.yml', __dir__)))
video_props['audio_offset'] = 0 if video_props['audio_offset'].nil?

recording_dir = props['recording_dir']
playback_dir = video_props['playback_dir']
process_dir = "#{recording_dir}/process/video/#{meeting_id}"
raw_archive_dir = "#{recording_dir}/raw/#{meeting_id}"
donefile = "#{recording_dir}/status/processed/#{meeting_id}-video.done"
log_file = "#{props['log_dir']}/video/process-#{meeting_id}.log"

logger = if opts[:log_stdout]
           Logger.new(STDOUT)
         elsif opts[:stderr]
           Logger.new($stderr)
         else
           Logger.new(log_file)
         end
BigBlueButton.logger = logger

if File.exist?(donefile)
  logger.warn 'This processing script has already been run'
  exit 0
end

FileUtils.mkdir_p process_dir

logger.info 'Reading basic recording information'
events = Nokogiri::XML(File.open("#{raw_archive_dir}/events.xml"))
initial_timestamp = BigBlueButton::Events.first_event_timestamp(events)
final_timestamp = BigBlueButton::Events.last_event_timestamp(events)
duration = BigBlueButton::Events.get_recording_length(events)
metadata = events.at_xpath('/recording/metadata')

layout_name = video_props['default_layout_name']
if ! metadata['video-playback-layout-name'].nil?
  value = metadata['video-playback-layout-name']
  if video_props['layout'].has_key?(value)
    layout_name = value
  else
    logger.warn "No definition for video playback layout #{value}, using default #{layout_name}"
  end
end

logger.info 'Generating video events list'

# Webcams
webcam_edl = BigBlueButton::Events.create_webcam_edl(events, raw_archive_dir, props['show_moderator_viewpoint'])
logger.debug 'Webcam EDL:'
BigBlueButton::EDL::Video.dump(webcam_edl)

# Deskshare
deskshare_edl = BigBlueButton::Events.create_deskshare_edl(events, raw_archive_dir)
logger.debug 'Deskshare EDL:'
BigBlueButton::EDL::Video.dump(deskshare_edl)

video_edl = BigBlueButton::EDL::Video.merge(webcam_edl, deskshare_edl)

logger.debug 'Merged Video EDL:'
BigBlueButton::EDL::Video.dump(video_edl)

logger.info 'Applying recording start/stop events to video'
video_edl = BigBlueButton::Events.edl_match_recording_marks_video(video_edl, events, initial_timestamp, final_timestamp)
logger.debug 'Trimmed Video EDL:'
BigBlueButton::EDL::Video.dump(video_edl)

logger.info 'Checking whether webcams were used'
have_webcams = BigBlueButton::Events.have_webcam_events(events)
if have_webcams
  logger.info('Webcams were use in this session')
else
  logger.info('No webcams were used in this session')
end

logger.info('Checking whether desktop sharing was used')
have_deskshare = BigBlueButton::Events.have_deskshare_events(events)
if have_deskshare
  logger.info('Desktop sharing was used in this session')
else
  logger.info('No desktop sharing was used in this session')
end

logger.info 'Checking whether the presentation area was used'
have_presentation = BigBlueButton::Events.have_presentation_events(events)
if have_presentation
  logger.info('Have presentation events, rendering presentation area')
else
  logger.info('No presentation events found')
end

if !have_presentation && !have_webcams
  logger.info('This recording has neither webcams or presentation')
  logger.info("Re-enabling presentation area, so the video isn't blank...")
  have_presentation = true
end

presentation_edl = nil
if have_presentation
  # The presentation video gets special treatment
  presentation_video = "#{process_dir}/presentation.mkv"
  presentation_edl = [
    {
      timestamp: 0,
      areas: { presentation: [{ filename: presentation_video, timestamp: 0 }] }
    },
    {
      timestamp: duration,
      areas: { presentation: [] }
    }
  ]
else
  presentation_edl = [
    {
      timestamp: 0,
      areas: { presentation: [] }
    }
  ]
end
logger.debug 'Presentation EDL:'
BigBlueButton::EDL::Video.dump(presentation_edl)

video_edl = BigBlueButton::EDL::Video.merge(presentation_edl, video_edl)
logger.debug 'Merged Video EDL with Presentation:'
BigBlueButton::EDL::Video.dump(video_edl)

logger.info 'Generating audio events list'
audio_edl = BigBlueButton::AudioEvents.create_audio_edl(events, raw_archive_dir)
logger.debug 'Audio EDL:'
BigBlueButton::EDL::Audio.dump(audio_edl)

logger.info 'Applying recording start/stop events to audio'
audio_edl = BigBlueButton::Events.edl_match_recording_marks_audio(audio_edl, events, initial_timestamp, final_timestamp)
logger.debug 'Trimmed Audio EDL:'
BigBlueButton::EDL::Audio.dump(audio_edl)

logger.info 'Rendering audio'
audio = BigBlueButton::EDL::Audio.render(audio_edl, "#{process_dir}/audio")

logger.info 'Rendering audio groups'
audio_groups = BigBlueButton::AudioProcessor.process_audio_groups(raw_archive_dir, "#{process_dir}/audio_group")
# convert language to code to ISO 639-2 so ffmpeg can understand it in the metadata
audio_groups.transform_keys! { |key| LANGUAGE_MAP[key.split('|').last[0,2]] }

if BigBlueButton::Events.screenshare_has_audio?(events, "#{raw_archive_dir}/deskshare")
  logger.info('Generating audio events list for deskshare')
  deskshare_audio_edl = BigBlueButton::AudioEvents.create_deskshare_audio_edl(events, "#{raw_archive_dir}/deskshare")
  logger.debug('Deskshare audio EDL:')
  BigBlueButton::EDL::Audio.dump(deskshare_audio_edl)

  logger.info('Applying recording start/stop events to deskshare audio')
  deskshare_audio_edl = BigBlueButton::Events.edl_match_recording_marks_audio(
    deskshare_audio_edl, events, initial_timestamp, final_timestamp
  )
  logger.debug('Trimmed deskshare audio EDL:')
  BigBlueButton::EDL::Audio.dump(deskshare_audio_edl)

  logger.info('Rendering deskshare audio')
  deskshare_audio = BigBlueButton::EDL::Audio.render(deskshare_audio_edl, "#{process_dir}/deskshare_audio")

  logger.info('Mixing meeting audio and deskshare audio')
  audio = BigBlueButton::EDL::Audio.mixer([audio, deskshare_audio], "#{process_dir}/mixed_audio")
end

# Select the layout based on what video sections are available
layout = \
  if have_webcams
    if have_presentation || have_deskshare
      video_props['layout'][layout_name]['regular']
    else
      video_props['layout'][layout_name]['nopresentation']
    end
  else
    video_props['layout'][layout_name]['nowebcam']
  end

layout.symbolize_keys!
layout[:areas].each do |area|
  area.symbolize_keys!
  area[:name] = area[:name].to_sym
end

if have_presentation
  logger.info 'Creating presentation area video'
  presentation_area = layout[:areas].detect { |area| area[:name] == :presentation }

  BigBlueButton.execute(
    [
      'bbb-presentation-video',
      '-i', raw_archive_dir,
      '-w', presentation_area[:width].to_s, '-h', presentation_area[:height].to_s, '-r', layout[:framerate].to_s,
      '-o', presentation_video
    ],
    true
  )
end

video_edl = BigBlueButton::EDL::Video.sort(video_edl)

logger.info 'Rendering video'
video = BigBlueButton::EDL::Video.render(video_edl, layout, "#{process_dir}/video")

metadata_link = "#{props['playback_protocol']}://#{props['playback_host']}/playback/video/#{meeting_id}/"
link_mp4 = false
if BigBlueButton.isset("MCONF_REC_WORKER_FORMAT_VIDEO_PLAYBACK_LINK_TO_MP4")
  link_mp4 = ENV["MCONF_REC_WORKER_FORMAT_VIDEO_PLAYBACK_LINK_TO_MP4"] == "true"
end
if ! metadata['video-playback-link-to-mp4'].nil?
  link_mp4 = metadata['video-playback-link-to-mp4'].to_s == "true"
end
if link_mp4
  I18n.available_locales = [:en]
  # remove accents
  sanitized_meeting_name = I18n.transliterate(metadata['meetingName'])
  # replace any unwanted sequence of characters with an underscore (to be safe as filename)
  sanitized_meeting_name = sanitized_meeting_name.gsub /[^a-z0-9\-]+/i, '_'
  # include at the and 4 random characters to make it harder to guess
  sanitized_filename = "#{sanitized_meeting_name}-#{SecureRandom.hex(2)}"

  logger.info "Encoding output files to #{video_props['formats'].length} formats"
  video_props['formats'].each_with_index do |format|
    format.symbolize_keys!
    logger.info "  #{format[:mimetype]}"
    BigBlueButton::EDL.encode(audio, video, format, "#{process_dir}/#{sanitized_filename}", video_props['audio_offset'], audio_groups)
  end
  final_video_path = File.basename(Dir.glob("#{process_dir}/#{sanitized_filename}.*").first)
  metadata_link = "#{props['playback_protocol']}://#{props['playback_host']}/video/#{meeting_id}/#{final_video_path}"
else
  logger.info "Encoding output files to #{video_props['formats'].length} formats"
  video_props['formats'].each_with_index do |format, i|
    format.symbolize_keys!
    logger.info "  #{format[:mimetype]}"
    BigBlueButton::EDL.encode(audio, video, format, "#{process_dir}/video-#{i}", video_props['audio_offset'], audio_groups)
  end

  logger.info('Generating closed captions')
  ret = BigBlueButton.exec_ret('utils/gen_webvtt', '-i', raw_archive_dir, '-o', process_dir)
  raise 'Generating closed caption files failed' if ret != 0

  captions = JSON.parse(File.read("#{process_dir}/captions.json"))

  # Generate the support files for chat events
  have_chat = false
  begin
    logger.info 'Processing chat events'
    chats = BigBlueButton::Events.get_chat_events(events, initial_timestamp, final_timestamp, props)
    have_chat = true unless chats.empty?

    # Output the chat events to the popcorn events file
    popcorn_events = Nokogiri::XML::Builder.new do |xml|
      xml.popcorn do
        chats.each do |chat|
          chattimeline = {
            in: (chat[:in] / 1000.0).round(1),
            id: chat[:id],
            direction: 'down',
            name: chat[:sender],
            senderId: chat[:sender_id],
            chatEmphasizedText: chat[:chatEmphasizedText],
            senderRole: chat[:senderRole],
            message: chat[:message],
            replyToMessageId: chat[:replyToMessageId],
            lastEditedTimestamp: chat[:lastEditedTimestamp],
            target: 'chat',
          }
          chattimeline[:out] = (chat[:out] / 1000.0).round(1) unless chat[:out].nil?
          chattimeline[:reactions] = JSON.generate(chat[:reactions]) unless chat[:reactions].nil?
          xml.chattimeline(**chattimeline)
        end
      end
    end
    File.write("#{process_dir}/video.xml", popcorn_events.to_xml)
  end

  # Publishing support files

  logger.info 'Generating index page'
  index_template = "#{playback_dir}/index.html.erb"
  index_erb = ERB.new(File.read(index_template))
  index_erb.filename = index_template
  File.write(
    "#{process_dir}/index.html",
    index_erb.result_with_hash(
      captions: captions,
      haveChat: have_chat,
      meetingName: metadata['meetingName'],
      video_props: video_props
    )
  )

  logger.info 'Copying css and js support files'
  FileUtils.cp_r("#{playback_dir}/css", process_dir)
  FileUtils.cp_r("#{playback_dir}/js", process_dir)
  FileUtils.cp_r("#{playback_dir}/video-js", process_dir)
end

logger.info 'Generating metadata xml'
metadata_xml = Nokogiri::XML::Builder.new do |xml|
  xml.recording do
    xml.id(meeting_id)
    xml.state('available')
    xml.published('true')
    xml.start_time(start_real_time)
    xml.end_time(start_real_time + final_timestamp - initial_timestamp)
    xml.playback do
      xml.format('video')
      xml.link(metadata_link)
      xml.duration(duration)
    end
    xml.meta do
      metadata.attributes.each do |k, v|
        xml.method_missing(k, v)
      end
    end
  end
end
File.write("#{process_dir}/metadata.xml", metadata_xml.to_xml)

BigBlueButton.add_raw_size_to_metadata(process_dir, raw_archive_dir)

logger.info 'Processing successfully completed, writing done file'

File.write(donefile, "Processed #{meeting_id}")
