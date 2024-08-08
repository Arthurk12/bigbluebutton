#!/usr/bin/ruby
# encoding: UTF-8

#
# BigBlueButton open source conferencing system - http://www.bigbluebutton.org/
#
# Copyright (c) 2012 BigBlueButton Inc. and by respective authors (see below).
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU Lesser General Public License as published by the Free
# Software Foundation; either version 3.0 of the License, or (at your option)
# any later version.
#
# BigBlueButton is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for more
# details.
#
# You should have received a copy of the GNU Lesser General Public License along
# with BigBlueButton; if not, see <http://www.gnu.org/licenses/>.
#

require "base64"
require "optimist"
require "yaml"
require "fileutils"
require "json"
require 'net/http'
require 'uri'
require File.expand_path("../../../lib/recordandplayback", __FILE__)

opts = Optimist::options do
  opt :meeting_id, "Record ID to transcribe", :type => String
  opt :force, "Force recording to be transcribed, no matter the matchers", :type => :flag, :default => false
  opt :log_stdout, "Log to STDOUT", :type => :flag
  opt :async, "Do not block until it's completed", :type => :flag, :default => false
end
meeting_id = opts[:meeting_id]

log_dir = "/var/log/bigbluebutton/transcribe"
FileUtils.mkdir_p log_dir

logger = opts[:log_stdout] ? Logger.new(STDOUT) : Logger.new("#{log_dir}/#{meeting_id}.log")
logger.level = Logger::INFO
BigBlueButton.logger = logger

props = YAML::load(File.open(File.expand_path('../transcribe.yml', __FILE__)))
if BigBlueButton.isset("MCONF_REC_CUSTOM_TRANSCRIBE_YML_B64")
  override_props = YAML::load(Base64.decode64(ENV["MCONF_REC_CUSTOM_TRANSCRIBE_YML_B64"]))
  props.merge!(override_props)
end

gladia_key = props["gladia_key"]
gladia_timeout = props["gladia_timeout"]
gladia_diarization = props["gladia_diarization"]
gladia_summarization = props["gladia_summarization"]
gladia_summarization_type = props["gladia_summarization_type"]
language_code = props["language_code"]
language_name = props["language_name"]

published_dir = "/var/bigbluebutton/published/presentation/#{meeting_id}"
vtt_file = "#{published_dir}/caption_#{language_code}.vtt"
captions_json = "#{published_dir}/captions.json"
speech_dir = "#{published_dir}/speech"
audio_file = "#{speech_dir}/recording.ogg"

metadata_xml = "#{published_dir}/metadata.xml"
metadata = Nokogiri::XML(File.open(metadata_xml)) { |x| x.noblanks }
exit 0 if ! File.exists? metadata_xml

async_file = "#{published_dir}/.transcription_async_id"
result_url = nil
transcription_status = {}

def get_result(result_url, gladia_key)
  url = URI(result_url)
  http = Net::HTTP.new(url.host, url.port)
  http.use_ssl = true
  request = Net::HTTP::Get.new(url)
  request['x-gladia-key'] = gladia_key
  response = http.request(request)
  return JSON.parse(response.read_body)
end

def get_userName_id_mapping(json_data)
  ids_mapping = {}
  json_data.each do |key, value|
    ids_mapping[value["userName"]] = key
  end
  ids_mapping
end

def intersection_length(start1, end1, start2, end2)
  # Determine the start and end of the overlapping interval
  overlap_start = [start1, start2].max
  overlap_end = [end1, end2].min

  # Calculate the intersection length
  overlap_end > overlap_start ? overlap_end - overlap_start : 0
end

def find_users_by_interval(json_data, start_timestamp, end_timestamp)
  matching_users_and_times = []

  json_data.each do |key, value|
    user_name = value["userName"]
    events = value["events"]

    events.each do |event|
      intersection_time = intersection_length(start_timestamp, end_timestamp, event["start"], event["stop"])
      if intersection_time > 0
        user_entry = matching_users_and_times.find { |entry| entry[0] == user_name }
        if !user_entry
          matching_users_and_times << [user_name, intersection_time]
        else
          # new intersecation for the same user, increment time
          user_entry[1] += intersection_time
        end
      end
    end
  end

  # Order by matched intersection time in descending order
  sorted = matching_users_and_times.sort_by { |_, time| -time }
  sorted_names = sorted.map { |name, time| name }

  matching_users_and_times.empty? ? nil : sorted_names.join(', ')
end

if File.exists? async_file
  result_url = File.read(async_file)
  transcription_status = get_result(result_url, gladia_key)
else
  # Do not generate transcription if the metadata check doesn't match
  match = false
  props['matcher'].each do |item|
    BigBlueButton.logger.info("Testing if #{item['xpath']}=#{item['value']}")

    node = metadata.at_xpath(item['xpath'])

    if ! node.nil? && node.text == item['value']
      match = true
      break
    end
  end
  if ! ( match or opts[:force] )
    BigBlueButton.logger.info("No match found")
    exit 0
  end

  BigBlueButton.logger.info("Generating #{language_code} transcription for #{meeting_id}")

  FileUtils.mkdir_p speech_dir
  if ! File.exist?(audio_file)
    raw_dir = "/var/bigbluebutton/recording/raw/#{meeting_id}"
    if Dir.exist?(raw_dir)
      BigBlueButton::EDL::Audio::FFMPEG_WF_CODEC = 'libopus'
      BigBlueButton::EDL::Audio::FFMPEG_WF_ARGS = ['-c:a', BigBlueButton::EDL::Audio::FFMPEG_WF_CODEC, '-f', 'ogg']
      BigBlueButton::AudioProcessor.process(raw_dir, "#{speech_dir}/audio")
    elsif Dir.exist?(published_dir)
      command = ""
      if File.exist?("#{published_dir}/video/webcams.webm")
        command = "ffmpeg -i #{published_dir}/video/webcams.webm -vn -af aformat=s16:48000 #{audio_file}"
      elsif File.exist?("#{published_dir}/video/webcams.mp4")
        command = "ffmpeg -i #{published_dir}/video/webcams.mp4 -vn -af aformat=s16:48000 #{audio_file}"
      else
        BigBlueButton.logger.error("Can't find any file to extract the audio file")
        exit 1
      end
      BigBlueButton.execute(command)
    end
  end

  if File.exist?(audio_file)
    BigBlueButton.logger.info("Uploading audio file #{audio_file} using Gladia API Key #{gladia_key}")

    url = URI("https://api.gladia.io/v2/upload")
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    http.read_timeout = gladia_timeout

    request = Net::HTTP::Post.new(url)
    request['Content-Type'] = 'multipart/form-data'
    request['x-gladia-key'] = gladia_key
    form_data = [['audio', File.open(audio_file)]]
    request.set_form form_data, 'multipart/form-data'

    response = http.request(request)

    BigBlueButton.logger.info("Upload response: #{response.read_body}")

    audio_url = JSON.parse(response.read_body)['audio_url']

    url = URI("https://api.gladia.io/v2/transcription")
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true

    talking_info = JSON.parse(File.read("#{published_dir}/talking.json"))

    request = Net::HTTP::Post.new(url)
    request['Content-Type'] = 'application/json'
    request['x-gladia-key'] = gladia_key
    request.body = JSON.dump({
      "audio_url" => audio_url,
      "diarization" => gladia_diarization,
      "diarization_config" => {
        "number_of_speakers" => talking_info.count,
        "min_speakers" => talking_info.count - 1, 
        "max_speakers" => talking_info.count,
      },
      "subtitles" => !gladia_diarization,
      "subtitles_config" => {
        "formats" => ["vtt"]
      },
      "detect_language" => true,
      "enable_code_switching" => false,
      "summarization" => gladia_summarization,
      "summarization_config" => { "type" => gladia_summarization_type}
    })

    BigBlueButton.logger.info("Transcribing #{audio_url} using gladia api with key #{gladia_key}")

    response = http.request(request)

    BigBlueButton.logger.info("Transcription response: #{response.read_body}")

    result_url = JSON.parse(response.read_body)['result_url']

    if opts[:async]
      File.open(async_file, "w") do |f|
        f.write(result_url)
      end
      exit 0
    end
  else
    BigBlueButton.logger.error("Could not find #{audio_file}")
    exit 1
  end
end

if opts[:async]
  if transcription_status['status'] != 'done'
    BigBlueButton.logger.info("Transcription async #{result_url} is still not ready")
    exit 0
  end
  File.delete async_file
else
  BigBlueButton.logger.info("Wait for it to be done, transcription url: #{result_url}")
  begin
    while transcription_status['status'] != 'done'
      transcription_status = get_result(result_url, gladia_key)
      BigBlueButton.logger.info("Status: #{transcription_status['status']}")
      sleep(1)
    end
  rescue Exception => e
    BigBlueButton.logger.error "Something went wrong while waiting for transcription to be done!"
    BigBlueButton.logger.error e
    exit 1
  end
  if transcription_status['status'] != 'done'
    BigBlueButton.logger.error("Transcription #{result_url} is not done")
    exit 1
  end
  BigBlueButton.logger.info("Done")
end

if transcription_status['status'] == 'error'
  BigBlueButton.logger.error(operation.results.message)
  exit 1
end

results = transcription_status['result']
BigBlueButton.logger.info("Transciption successfull, saving Gladia resutls...")
File.open("#{speech_dir}/gladia.json", 'w') { |file| file.write(results.to_json) }

if ! results.empty?
  gladia_out_vtt = ""
  if gladia_diarization
    BigBlueButton.logger.info("Generating vtt file with speaker data...")

    sequence_number = 1
    last_speaker = nil
    last_speakers = []
    gladia_out_vtt = "WEBVTT\n\n"

    talking_info = JSON.parse(File.read("#{published_dir}/talking.json"))
    ids_mapping = get_userName_id_mapping(talking_info)
    speaker_mapping = {}

    results['transcription']['utterances'].each do |paragraph|
      time = "#{Time.at(paragraph['start']).utc.strftime("%T.%L")} --> #{Time.at(paragraph['end']).utc.strftime("%T.%L")}"
      talking_users = find_users_by_interval(talking_info, paragraph['start'], paragraph['end'] )
      speaker = paragraph['speaker']
      if !talking_users.nil? and talking_users.split(',').size > 1
        # when we have more than one speaker, try to match with gladia if available
        gladia_speaker = speaker_mapping[speaker]
        if talking_users.split(", ").include?(gladia_speaker)
          talking_users = gladia_speaker
        else
          # otherwise, use the user with most intersection time
          talking_users = talking_users.split(", ")[0]
        end
      end
      if !talking_users.nil? and talking_users != last_speakers
        gladia_out_vtt += "NOTE MCONF_CUE_META {\"voice\":\"#{talking_users}\"}\n\n"
      end
      if !speaker_mapping[speaker] and !talking_users.nil?
        most_talking_user = talking_users.split(", ")[0]
        if speaker_mapping.key(most_talking_user).nil?
          speaker_mapping[speaker] = most_talking_user
        end
      end
      # see if we have the talker from before
      if talking_users.nil? and !speaker_mapping[speaker].nil?
        gladia_out_vtt += "NOTE MCONF_CUE_META {\"voice\":\"#{speaker_mapping[speaker]}\"}\n\n"
        last_speakers = speaker_mapping[speaker]
      end
      last_speaker = speaker
      last_speakers = talking_users if !talking_users.nil?
      gladia_out_vtt += "#{sequence_number}\n#{time}\n#{paragraph['text']}\n\n"

      # add username and id to the gladia result
      paragraph['user_name'] = last_speakers
      speakers_ids = last_speakers.dup
      ids_mapping.each do |name, id|
        speakers_ids.gsub!(name, id) if speakers_ids.include?(name)
      end
      paragraph['user_id'] = speakers_ids

      sequence_number += 1
    end
    BigBlueButton.logger.info("Saving gladia results with speaker name and id to published results...")
    File.open("#{published_dir}/transcription.json", 'w') { |file| file.write(results.to_json) }
  else
    BigBlueButton.logger.info("Extracting vtt file...")
    gladia_out_vtt = results['transcription']['subtitles'][0]['subtitles']
  end

  BigBlueButton.logger.info("Saving #{language_code} VTT file for #{meeting_id}")

  if File.exists? vtt_file
    # backup existing vtt file
    BigBlueButton.logger.info("#{vtt_file} already exists, backing up...")
    FileUtils.mv(vtt_file, "#{vtt_file}.#{Time.now.strftime("%Y%m%d%H%M")}")
  end

  File.open(vtt_file, 'w') { |file| file.write(gladia_out_vtt) }

  BigBlueButton.logger.info("Editing #{meeting_id} captions JSON file")
  old_captions = []
  if File.exists? captions_json
    old_captions = JSON.parse(File.read(captions_json))
  end
  old_captions.reject! { |item| item["locale"] == language_code }
  captions = { "localeName" => language_name, "locale" => language_code }
  old_captions << captions
  File.open(captions_json, "w") do |f|
    f.write(old_captions.to_json)
  end
else
  BigBlueButton.logger.error("Could not transcribe #{transcription_status}")
end

BigBlueButton.logger.info("Deleting transcription #{result_url} from gladia")
url = URI(result_url)
http = Net::HTTP.new(url.host, url.port)
http.use_ssl = true
request = Net::HTTP::Delete.new(url)
request["x-gladia-key"] = gladia_key
response = http.request(request)

if BigBlueButton.isset("MCONF_REC_WORKER_TRANSCRIBE_KEEP_SPEECH_DIR") and ENV["MCONF_REC_WORKER_TRANSCRIBE_KEEP_SPEECH_DIR"] == "true"
  BigBlueButton.logger.info("Not deleting #{speech_dir} due to MCONF_REC_WORKER_TRANSCRIBE_KEEP_SPEECH_DIR")
else
  BigBlueButton.logger.info("Deleting #{speech_dir}")
  FileUtils.remove_dir(speech_dir)
end

exit 0
