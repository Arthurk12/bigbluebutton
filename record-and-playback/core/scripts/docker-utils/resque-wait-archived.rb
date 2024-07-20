#!/usr/bin/ruby
# frozen_string_literal: true

# Copyright © 2017 BigBlueButton Inc. and by respective authors.
#
# This file is part of BigBlueButton open source conferencing system.
#
# BigBlueButton is free software: you can redistribute it and/or modify it
# under the terms of the GNU Lesser General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your
# option) any later version.
#
# BigBlueButton is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public License for more
# details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with BigBlueButton.  If not, see <http://www.gnu.org/licenses/>.

require_relative '../../lib/recordandplayback'

require 'recordandplayback/workers'
require 'rubygems'
require 'yaml'
require 'fileutils'
require 'resque'
require 'rb-inotify'

class StopSignalException < StandardError
end

def parse_meeting_id(done_file)
  id = File.basename(done_file, '.done')
  if (match = /^([0-9a-f]+-[0-9]+)$/.match(id))
    { meeting_id: match[1], break_timestamp: nil }
  elsif (match = /^([0-9a-f]+-[0-9]+)-([0-9]+)$/.match(id))
    { meeting_id: match[1], break_timestamp: match[2] }
  else
    BigBlueButton.logger.warn("Recording done file #{done_file} has invalid format")
    nil
  end
end

def process_archived_meetings(recording_dir, done_file)
  id = File.basename(done_file, '.done')
  BigBlueButton.logger.debug("Seen new archived done file for #{id}")
  attrs = parse_meeting_id(id)
  return if attrs.nil?

  BigBlueButton.logger.info("Enqueueing job to presentation #{attrs.inspect}")
  Resque.enqueue(BigBlueButton::Resque::PresentationWorker, attrs)
  FileUtils.rm_f(done_file)
end

begin
  props = BigBlueButton.read_props

  redis_host = props['redis_workers_host'] || props['redis_host']
  redis_port = props['redis_workers_port'] || props['redis_port']
  Resque.redis = "#{redis_host}:#{redis_port}"

  BigBlueButton.logger = Logger.new("/var/log/bigbluebutton/starter.log", 'daily')
  BigBlueButton.logger.level = Logger::DEBUG

  BigBlueButton.logger.debug('Running rap-starter...')

  recording_dir = props['recording_dir']
  archived_status_dir = "#{recording_dir}/status/archived"

  # Listen the directories for when new files are created
  notifier = INotify::Notifier.new

  BigBlueButton.logger.info("Setting up inotify watch on #{archived_status_dir}")
  notifier.watch(archived_status_dir, :moved_to, :create) do |event|
    next if event.name.end_with?('.fail')

    process_archived_meetings(recording_dir, event.absolute_name)
  end

  BigBlueButton.logger.info('Waiting for new recordings...')
  Signal.trap('INT') { raise StopSignalException, 'INT' }
  Signal.trap('TERM') { raise StopSignalException, 'TERM' }
  notifier.run
rescue StopSignalException
  notifier.stop
end
