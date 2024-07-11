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

module BigBlueButton
  module Resque
    class ArchiveWorker < BaseWorker
      @queue = 'rap:archive'

      def perform
        super do
          @logger.info("Running archive worker for #{@full_id}")
          @publisher.put_archive_started(@meeting_id)

          remove_status_files

          script = File.join(BigBlueButton.rap_scripts_path, 'archive', 'archive.rb')
          if @break_timestamp.nil?
            ret, step_time = run_script(script, '-m', @meeting_id)
          else
            ret, step_time = run_script(script, '-m', @meeting_id, '-b', @break_timestamp)
          end

          step_succeeded = (
            ret.zero? &&
            (File.exist?(@archived_done) || File.exist?(@archived_norecord)) &&
            !File.exist?(@archived_fail)
          )

          norecord = File.exist?(@archived_norecord)
          @publisher.put_archive_norecord(@meeting_id) if norecord

          if step_succeeded and ! norecord
            # split_recording will return new record_ids
            new_recordings = split_recording(@meeting_id)
            # schedule next step for new record_ids
            new_recordings.each{ |meeting_id| schedule_next_step_helper(meeting_id) }
          end

          @publisher.put_archive_ended(@meeting_id, success: step_succeeded, step_time: step_time)

          if step_succeeded
            @logger.info("Successfully archived #{@full_id}")
          else
            @logger.error("Failed to archive #{@full_id}")
            FileUtils.touch(@archived_fail)
          end
          @logger.debug("Finished archive worker for #{@full_id}")

          raise WorkerNoRecordHalt, "Meeting #{@full_id} had no recording marks" if norecord

          step_succeeded
        end
      end

      def split_recording(meeting_id, parent_id = nil, index = 0)
        parent_id ||= meeting_id

        props = BigBlueButton.read_props
        raw_dir = "#{props["recording_dir"]}/raw/#{meeting_id}"
        events_filename = "#{raw_dir}/events.xml"

        doc = Nokogiri::XML(open(events_filename).read) { |x| x.noblanks }

        # skip first start recording event
        doc.xpath("/recording/event[@eventname='RecordStatusEvent' and ./status='true']").drop(1).each do |event|
          node = event.at_xpath("./continue")
          if (node.nil? and props['continue_recording_by_default'] == false) or (! node.nil? and node.text == "false")
            # new recording will be created
            FileUtils.cp events_filename, "#{events_filename}.orig" if ! File.exists? "#{events_filename}.orig"

            m = /^(?<prefix>\w+)-(?<timestamp>\d+)$/.match meeting_id

            timestamp_new = event.at_xpath('timestampUTC').text
            # new record_id structure is same prefix + timestamp of the start recording event
            record_id = "#{m[:prefix]}-#{timestamp_new}"
            @logger.info("Detaching record_id #{record_id} from #{parent_id}, index #{index + 1}")
            raw_dir_new = "#{props["recording_dir"]}/raw/#{record_id}"
            FileUtils.cp_r raw_dir, raw_dir_new

            events_filename_new = "#{raw_dir_new}/events.xml"
            doc_new = Nokogiri::XML(open(events_filename_new).read) { |x| x.noblanks }

            # from the new recording, remove any recording event that happened before
            doc_new.xpath("/recording/event[@eventname='RecordStatusEvent' and ./timestampUTC<#{timestamp_new}]").each{ |node| node.remove }
            # update attributes from events.xml
            doc_new.at_xpath('/recording').set_attribute('id', record_id)
            doc_new.at_xpath('/recording/metadata').set_attribute('splitRecordingIndex', index + 1)

            # record to file
            events_file_new = File.new(events_filename_new, "w")
            events_file_new.write(doc_new.to_xml(:indent => 2))
            events_file_new.close

            # remove recording marks from original recording
            doc.xpath("/recording/event[@eventname='RecordStatusEvent' and ./timestampUTC>=#{timestamp_new}]").each{ |node| node.remove }
            doc.at_xpath('/recording/metadata').set_attribute('splitRecordingIndex', index)
            events_file = File.new(events_filename, "w")
            events_file.write(doc.to_xml(:indent => 2))
            events_file.close

            return [ record_id ] + split_recording(record_id, parent_id, index + 1)
          end
        end
        return []
      end

      def remove_status_files
        FileUtils.rm_f(@archived_done)
        FileUtils.rm_f(@archived_norecord)
        FileUtils.rm_f(@archived_fail)
      end

      def initialize(opts)
        super(opts)
        @step_name = 'archive'
        @archived_fail = "#{@recording_dir}/status/archived/#{@full_id}.fail"
        @archived_done = "#{@recording_dir}/status/archived/#{@full_id}.done"
        @archived_norecord = "#{@recording_dir}/status/archived/#{@full_id}.norecord"
      end
    end
  end
end
