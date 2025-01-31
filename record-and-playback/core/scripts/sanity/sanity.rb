#!/usr/bin/ruby
# encoding: UTF-8
#
# BigBlueButton open source conferencing system - http://www.bigbluebutton.org/
#
# Copyright (c) 2012 BigBlueButton Inc. and by respective authors (see below).
#
# This program is free software; you can redistribute it and/or modify it under the
# terms of the GNU Lesser General Public License as published by the Free Software
# Foundation; either version 3.0 of the License, or (at your option) any later
# version.
#
# BigBlueButton is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License along
# with BigBlueButton; if not, see <http://www.gnu.org/licenses/>.
#

require File.expand_path('../../../lib/recordandplayback', __FILE__)
require 'logger'
require 'optimist'
require 'yaml'
require "nokogiri"
require "redis"
require "fileutils"

props = BigBlueButton.read_props
log_dir = props['log_dir']
audio_dir = props['raw_audio_src']
recording_dir = props['recording_dir']
raw_archive_dir = "#{recording_dir}/raw"
redis_host = props['redis_host']
redis_port = props['redis_port']
redis_password = props['redis_password']

opts = Optimist::options do
  opt :meeting_id, "Meeting id to archive", type: :string
  opt :break_timestamp, "Chapter break end timestamp", type: :string
end
Optimist::die :meeting_id, "must be provided" if opts[:meeting_id].nil?

meeting_id = opts[:meeting_id]
break_timestamp = opts[:break_timestamp]


BigBlueButton.logger = Logger.new("#{log_dir}/sanity.log", 'daily' )
logger = BigBlueButton.logger

def check_events_xml(raw_dir,meeting_id)
  filepath = "#{raw_dir}/#{meeting_id}/events.xml"
  raise Exception,  "Events file doesn't exists." if not File.exists?(filepath)
  bad_doc = Nokogiri::XML(File.open(filepath)) { |config| config.options = Nokogiri::XML::ParseOptions::STRICT }
end

# Check if ogg file has corrupted bytes at the beginning and remove them
# Valid files start with "Ogg"
def checkAndFixOggCorruptedInitialBytes(file)
  tail = ['tail', '-c']
  # open file as binary, read X bytes and immediately closes
  oggIndex = File.open(file, 'rb') { |io| io.read(2048) }.index("Ogg")
  if oggIndex && oggIndex > 0
    # file does not start with Ogg, remove first oggIndex+1 bytes
    BigBlueButton.logger.info("#{oggIndex+1} Corrupted bytes found before Ogg string, fixing...")
    tail_cmd = [*tail]
    tail_cmd += ["+#{oggIndex+1}", file]
    output = "fixed_#{file}"
    ret = BigBlueButton.exec_redirect_ret(output,*tail_cmd)
    if ret != 0
      BigBlueButton.logger.warn("Failed to fix initial bytes of #{file}")
      FileUtils.rm_f(output)
      return -1
    end
    BigBlueButton.logger.info("Fixed bytes, cleaning up original file")
    # keep original ogg file, so we have the possibility to inspect it later on
    FileUtils.mv(file, "#{file}.orig")
    FileUtils.mv(output, file)
    return 0
  else
    return 1
  end
end

def remux_files(directory)
  ffmpeg = ['ffmpeg', '-y', '-v', 'warning', '-nostats', '-max_error_rate', '1.0']
  if File.directory?(directory)
    FileUtils.cd(directory) do

      BigBlueButton.logger.info("Remuxing audio files to fix corrupted streams")
      Dir.glob("*.opus").each do |audio|
        BigBlueButton.logger.info("Remuxing #{audio}")
        ffmpeg_cmd = [*ffmpeg]
        output = "remuxed_#{audio}"
        ffmpeg_cmd += ['-i', audio, '-c', 'copy', '-map', '0', output]
        ret = BigBlueButton.exec_ret(*ffmpeg_cmd)
        if ret != 0
          if File.size(audio) < 1000
            BigBlueButton.logger.warn("File size is less than 1000 bytes, probably empty file, will be ignored #{audio}")
            next
          end
          fixOggRet = checkAndFixOggCorruptedInitialBytes(audio)
          if fixOggRet == 0
            # file had corrupted initial bytes and is now fixed, remux again
            ret = BigBlueButton.exec_ret(*ffmpeg_cmd)
            if ret != 0
              FileUtils.rm_f(output)
              raise Exception, "Failed to remux #{audio} after fixing invalid bytes"
            end
          else
            FileUtils.rm_f(output)
            raise Exception, "Failed to remux #{audio}"
          end
        end

        BigBlueButton.logger.info("Remuxed, cleaning up original file")
        FileUtils.rm_f(audio)
        FileUtils.mv(output, audio)
      end
    end
  end
end

def self.check_talking_users_have_audio(events_xml, audio_dir)
  # Gather all participants who have talking events
  talking_events = BigBlueButton::Events.get_talking_events(events_xml)
  # Filter out those who have no talking events
  talking_participants = talking_events
    .select { |_participant_id, data| data[:events].any? }
    .keys

  # Parse AudioTrackPublishedEvent to see which participants actually published audio
  # and also check if the file physically exists on disk.
  # Map: participant_id -> Array of actual existing files
  published_audio_files = Hash.new { |h, k| h[k] = [] }

  events_xml.xpath(
    "recording/event[@module='bbb-webrtc-sfu' and @eventname='AudioTrackPublishedEvent']"
  ).each do |event|
    participant_id = event.at_xpath('userId')&.text
    filename       = event.at_xpath('filename')&.text
    next if participant_id.nil? || filename.nil?

    # Derive the path used by the archive process
    # For example, if the published filename is "some-track.wav",
    # BigBlueButton’s code typically saves it into ".../audio/some-track.wav".
    file_path = File.join(audio_dir, File.basename(filename))

    # Check if this file actually exists on disk
    if File.exist?(file_path)
      published_audio_files[participant_id] << file_path
    end
  end

  talking_participants.each do |participant_id|
    has_audio = published_audio_files[participant_id].any?
    BigBlueButton.logger.warn "User #{participant_id} talked but no audio files were found." if !has_audio
  end
end

# Determine the filenames for the done and fail files
if !break_timestamp.nil?
  done_base = "#{meeting_id}-#{break_timestamp}"
else
  done_base = meeting_id
end
sanity_done_file = "#{recording_dir}/status/sanity/#{done_base}.done"
sanity_fail_file = "#{recording_dir}/status/sanity/#{done_base}.fail"


begin
  logger.info("Starting sanity check for recording #{meeting_id}")
  if !break_timestamp.nil?
    logger.info("Break timestamp is #{break_timestamp}")
  end

  logger.info("Checking events.xml")
  check_events_xml(raw_archive_dir,meeting_id)

  logger.info("Checking if talking users have recorded audio tracks...")
  events_xml = Nokogiri::XML(File.open("#{raw_archive_dir}/#{meeting_id}/events.xml"))
  check_talking_users_have_audio(events_xml, "#{raw_archive_dir}/#{meeting_id}/audio")

  logger.info("Repairing audio files")
  remux_files("#{raw_archive_dir}/#{meeting_id}/audio")

  if break_timestamp.nil?
    # Either this recording isn't segmented, or we are working on the last
    # segment, so go ahead and clean up all the redis data.
    logger.info("Deleting keys")
    redis = BigBlueButton::RedisWrapper.new(redis_host, redis_port, redis_password)
    events_archiver = BigBlueButton::RedisEventsArchiver.new(redis)
    events_archiver.delete_events(meeting_id)
  end

  logger.info("creating sanity done files")
  File.open(sanity_done_file, "w") do |sanity_done|
    sanity_done.write("sanity check #{meeting_id}")
  end
rescue Exception => e
  BigBlueButton.logger.error("error in sanity check: " + e.message)
  BigBlueButton.logger.error(e.backtrace.join("\n"))
  File.open(sanity_fail_file, "w") do |sanity_fail|
    sanity_fail.write("error: " + e.message)
  end
end


