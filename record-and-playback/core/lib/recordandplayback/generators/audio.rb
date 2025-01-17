# Set encoding to utf-8
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


require 'fileutils'
require 'rubygems'
require 'nokogiri'
require 'builder'

module BigBlueButton
  class AudioEvents

    def self.create_audio_edl(events, archive_dir)
      audio_edl = []
      audio_dir = "#{archive_dir}/audio"
      audios = {}
      active_audios = []

      initial_timestamp = BigBlueButton::Events.first_event_timestamp(events)
      final_timestamp = BigBlueButton::Events.last_event_timestamp(events)

      # Initially start with silence
      audio_edl << {
        :timestamp => 0,
        :audio => nil
      }

      # Add events for recording start/stop
      events.xpath('/recording/event[@module="VOICE" or @module="bbb-webrtc-sfu"]').each do |event|
        timestamp = event['timestamp'].to_i - initial_timestamp
        case event['eventname']
        when 'StartRecordingEvent'
          filename = event.at_xpath('filename').text
          filename = "#{audio_dir}/#{File.basename(filename)}"
          audio_edl << {
            :timestamp => timestamp,
            :audio => { :filename => filename, :timestamp => 0 }
          }
        when 'StopRecordingEvent'
          filename = event.at_xpath('filename').text
          filename = "#{audio_dir}/#{File.basename(filename)}"
          if audio_edl.last[:audio] && audio_edl.last[:audio][:filename] == filename
            audio_edl.last[:original_duration] = timestamp - audio_edl.last[:timestamp]
            audio_edl << {
              :timestamp => timestamp,
              :audio => nil
            }
          end
        when 'AudioTrackPublishedEvent'
          filename = event.at_xpath('filename').text
          filename = "#{audio_dir}/#{File.basename(filename)}"
          audios[filename] = { :timestamp => timestamp }
          active_audios << filename
          edl_entry = {
            :timestamp => timestamp,
            :audios => []
          }
          active_audios.each do |filename|
            edl_entry[:audios] << {
              :filename => filename,
              :timestamp => timestamp - audios[filename][:timestamp]
            }
          end
          audio_edl << edl_entry
        when 'AudioTrackUnpublishedEvent'
          filename = event.at_xpath('filename').text
          filename = "#{audio_dir}/#{File.basename(filename)}"
          active_audios.delete(filename)
          edl_entry = {
            :timestamp => timestamp,
            :audios => []
          }
          active_audios.each do |filename|
            edl_entry[:audios] << {
              :filename => filename,
              :timestamp => timestamp - audios[filename][:timestamp]
            }
          end
          audio_edl << edl_entry
        end
      end

      audio_edl << {
        :timestamp => final_timestamp - initial_timestamp,
        :audio => nil
      }

      return audio_edl
    end

    def self.create_audio_group_edls(events, archive_dir)
      audio_groups_edl = {}
      audio_dir        = "#{archive_dir}/audio"

      # Holds information about each audio’s base timestamp (when it was published).
      audios        = {}
      # List of currently active audio references
      active_audios = []

      # Determine global start/end times
      initial_timestamp = BigBlueButton::Events.first_event_timestamp(events)
      final_timestamp   = BigBlueButton::Events.last_event_timestamp(events)

      #--------------------------------------------------------------------
      # Helper to build and append an EDL entry in audio_groups_edl
      #--------------------------------------------------------------------
      build_edl_entry = lambda do |group_id, timestamp, senders|
        # If we have no senders, and the last EDL entry wasn't already silence,
        # we append a silence entry.
        if senders.empty?
          last_entry = audio_groups_edl[group_id].last
          if last_entry && !last_entry[:audios].nil?
            audio_groups_edl[group_id] << {
              timestamp: timestamp,
              audios:    nil
            }
          end
          return
        end

        # Otherwise, build a list of active audios that match the senders.
        new_audios = []
        active_audios.each do |audio|
          filename = audio[:filename]
          user_id  = audio[:user_id]
          if senders.include?(user_id)
            # The timestamp offset inside this file is (current_time - time_when_published)
            base_offset = audios[filename][:timestamp]
            new_audios << {
              filename:  filename,
              timestamp: (timestamp - base_offset)
            }
          end
        end

        # Append this EDL entry (could be empty if no active_audios matched).
        audio_groups_edl[group_id] << {
          timestamp: timestamp,
          audios:    new_audios.empty? ? nil : new_audios
        }
      end

      # Parse AUDIO_GROUP / bbb-webrtc-sfu events
      events.xpath('/recording/event[@module="AUDIO_GROUP" or @module="bbb-webrtc-sfu"]').each do |event|
        timestamp = event['timestamp'].to_i - initial_timestamp
        eventname = event['eventname']

        case eventname
        when 'AudioTrackPublishedEvent'
          source = event.at_xpath('source')&.text
          next if source != 'microphone'
          user_id  = event.at_xpath('userId')&.text
          filename = File.basename(event.at_xpath('filename').text)
          filepath = "#{audio_dir}/#{filename}"
          # Keep track of the base timestamp for this file
          audios[filepath] = { timestamp: timestamp }
          # Mark this audio as active
          active_audios << { filename: filepath, user_id: user_id }
        when 'AudioTrackUnpublishedEvent'
          source = event.at_xpath('source')&.text
          next if source != 'microphone'
          filename = File.basename(event.at_xpath('filename').text)
          filepath = "#{audio_dir}/#{filename}"
          # Remove this file from the list of active audios
          active_audios.delete_if { |a| a[:filename] == filepath }
        when 'AudioGroupCreatedEvent'
          group_id = event.at_xpath('groupId')&.text
          # Initialize an EDL list for this group, starting with silence at t=0
          audio_groups_edl[group_id] = [
            { timestamp: 0, audios: nil }
          ]
          senders = event.at_xpath('senders')&.text&.split(',') || []
          build_edl_entry.call(group_id, timestamp, senders)
        when 'AudioGroupUpdatedEvent'
          group_id = event.at_xpath('groupId')&.text
          senders  = event.at_xpath('senders')&.text&.split(',') || []
          build_edl_entry.call(group_id, timestamp, senders)
        when 'AudioGroupDestroyedEvent'
          # Marks the group as ended at 'timestamp', so we add an entry with no audio
          group_id = event.at_xpath('groupId')&.text
          audio_groups_edl[group_id] << {
            timestamp: timestamp,
            audios:    nil
          }
        end
      end

      # Add final silence entry at the end of each group's timeline
      audio_groups_edl.each do |group_id, audio_edl|
        audio_edl << {
          timestamp: final_timestamp - initial_timestamp,
          audios:    nil
        }
      end
    
      audio_groups_edl
    end

    def self.create_deskshare_audio_edl(events, deskshare_dir)
      audio_edl = []

      initial_timestamp = BigBlueButton::Events.first_event_timestamp(events)
      final_timestamp = BigBlueButton::Events.last_event_timestamp(events)
      filename = ""

      # Initially start with silence
      audio_edl << {
        :timestamp => 0,
        :audio => nil
      }

      events.xpath('/recording/event[@module="bbb-webrtc-sfu" and (@eventname="StartWebRTCDesktopShareEvent" or @eventname="StopWebRTCDesktopShareEvent")]').each do |event|
        filename = event.at_xpath('filename').text
        # Determine the audio filename
        case event['eventname']
        when 'StartWebRTCDesktopShareEvent', 'StopWebRTCDesktopShareEvent'
          uri = event.at_xpath('filename').text
          filename = "#{deskshare_dir}/#{File.basename(uri)}"
        end
        raise "Couldn't determine audio filename" if filename.nil?
        # check if deskshare has audio
        fileHasAudio = !BigBlueButton::EDL::Audio.audio_info(filename)[:audio].nil?
        if (fileHasAudio)
          timestamp = event['timestamp'].to_i - initial_timestamp
          # Add the audio to the EDL
          case event['eventname']
          when 'StartWebRTCDesktopShareEvent'
            audio_edl << {
              :timestamp => timestamp,
              :audio => { :filename => filename, :timestamp => 0 }
            }
          when 'StopWebRTCDesktopShareEvent'
            if audio_edl.last[:audio] && audio_edl.last[:audio][:filename] == filename
              # Fill in the original/expected audo duration when available
              duration = event.at_xpath('duration')
              if !duration.nil?
                duration = duration.text.to_i
                audio_edl.last[:original_duration] = duration * 1000
              else
                audio_edl.last[:original_duration] = timestamp - audio_edl.last[:timestamp]
              end
              audio_edl << {
                :timestamp => timestamp,
                :audio => nil
              }
            end
          end
        else
          BigBlueButton.logger.debug " Screenshare without audio, ignoring..."
        end
      end

      audio_edl << {
        :timestamp => final_timestamp - initial_timestamp,
        :audio => nil
      }

      return audio_edl
    end

  end
end
