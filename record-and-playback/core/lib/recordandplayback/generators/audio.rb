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
        :audios => []
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
            :audios => [{ :filename => filename, :timestamp => 0 }]
          }
        when 'StopRecordingEvent'
          filename = event.at_xpath('filename').text
          filename = "#{audio_dir}/#{File.basename(filename)}"
          if audio_edl.last.dig(:audios, 0, :filename) == filename
            audio_edl.last[:original_duration] = timestamp - audio_edl.last[:timestamp]
            audio_edl << {
              :timestamp => timestamp,
              :audios => []
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
        :audios => []
      }

      return audio_edl
    end

    def self.create_audio_edl_with_groups(events, archive_dir)
      audio_dir = File.join(archive_dir, 'audio')
    
      main_audio_edl = [
        { timestamp: 0, audios: [] }
      ]
      # For each filename, store when it was published
      main_audios = {}
      # For quick lookup of which user published which filename (only if microphone)
      filename_to_user_id = {}
      # For quick lookup of the source for each filename (e.g. "microphone" or "screen_share_audio")
      filename_to_source = {}
      # Currently active filenames in main EDL
      main_active_filenames = []
    
      audio_groups_edl = {}
      # For group-based audio: keep track of base timestamp for each file
      group_audios = {}
      # Currently active group-audio references: array of { filename:, user_id: }
      group_active_audios = []
    
      # For each user, maintain a set of group IDs that user is currently in.
      # If user_in_groups[user_id].empty? => user is in NO group => mic audio can appear in main
      user_in_groups = Hash.new { |h, k| h[k] = Set.new }
    
      #--------------------------------------------------------------------------
      # Helper to build a new EDL entry for a group
      #--------------------------------------------------------------------------
      build_group_edl_entry = lambda do |group_id, timestamp, senders|
        # If we have no senders, and the last EDL entry wasn't silence, append silence
        if senders.empty?
          last_entry = audio_groups_edl[group_id].last
          if last_entry && !last_entry[:audios].empty?
            audio_groups_edl[group_id] << {
              timestamp: timestamp,
              audios:    []
            }
          end
          return
        end
    
        # Otherwise, build a list of active audios that match the senders
        new_audios = []
        group_active_audios.each do |audio|
          filename = audio[:filename]
          user_id  = audio[:user_id]
          if senders.include?(user_id)
            base_offset = group_audios[filename][:timestamp]
            new_audios << {
              filename:  filename,
              timestamp: timestamp - base_offset
            }
          end
        end
    
        # Append the EDL entry for this group
        audio_groups_edl[group_id] << {
          timestamp: timestamp,
          audios:    new_audios
        }
      end

      #--------------------------------------------------------------------------
      # Helper to (re)build a new EDL entry for the MAIN audio, at a given moment
      #--------------------------------------------------------------------------
      rebuild_main_edl_entry = lambda do |timestamp|
        # Build a new EDL entry from the currently active filenames in main
        edl_entry = {
          timestamp: timestamp,
          audios:    main_active_filenames.map do |fn|
            # offset = now - time when track was published
            {
              filename:  fn,
              timestamp: timestamp - main_audios[fn][:timestamp]
            }
          end
        }
        main_audio_edl << edl_entry
      end

      #--------------------------------------------------------------------------
      # Determine global start/end times
      #--------------------------------------------------------------------------
      initial_timestamp = BigBlueButton::Events.first_event_timestamp(events)
      final_timestamp   = BigBlueButton::Events.last_event_timestamp(events)

      #--------------------------------------------------------------------------
      # Gather *all* relevant events in chronological order
      #--------------------------------------------------------------------------
      all_events = events.xpath(
        '/recording/event[@module="VOICE" or @module="AUDIO_GROUP" or @module="bbb-webrtc-sfu"]'
      ).sort_by { |e| e['timestamp'].to_i }

      all_events.each do |event|
        event_ts = event['timestamp'].to_i - initial_timestamp
        name     = event['eventname']

        case name
        when 'AudioTrackPublishedEvent'
          pub_filename = event.at_xpath('filename')&.text
          next unless pub_filename
    
          pub_filepath = File.join(audio_dir, File.basename(pub_filename))
          user_id      = event.at_xpath('userId')&.text
          source       = event.at_xpath('source')&.text
    
          # Store in lookups
          main_audios[pub_filepath] = { timestamp: event_ts }
          filename_to_source[pub_filepath] = source
    
          # Only store user_id if source == 'microphone'
          if source == 'microphone'
            filename_to_user_id[pub_filepath] = user_id if user_id
          end
    
          #-----------------------------------
          # 1) MAIN audio logic
          #-----------------------------------
          if source == 'screen_share_audio'
            # Always in main
            main_active_filenames << pub_filepath
            rebuild_main_edl_entry.call(event_ts)
          elsif source == 'microphone'
            # Add if user not in any group or if user_id is missing
            if user_id.nil? || user_in_groups[user_id].empty?
              main_active_filenames << pub_filepath
              rebuild_main_edl_entry.call(event_ts)
            end
          else
            # For safety, let's include it in main by default:
            main_active_filenames << pub_filepath
            rebuild_main_edl_entry.call(event_ts)
          end
    
          #-----------------------------------
          # 2) GROUP audio logic (only if source == 'microphone')
          #-----------------------------------
          if source == 'microphone'
            group_audios[pub_filepath] = { timestamp: event_ts }
            group_active_audios << { filename: pub_filepath, user_id: user_id }
          end
    
        #------------------------------------------------------------------------
        # AudioTrackUnpublishedEvent
        #------------------------------------------------------------------------
        when 'AudioTrackUnpublishedEvent'
          unpub_filename = event.at_xpath('filename')&.text
          next unless unpub_filename
    
          unpub_filepath = File.join(audio_dir, File.basename(unpub_filename))
    
          # Remove from MAIN if it’s active
          if main_active_filenames.include?(unpub_filepath)
            main_active_filenames.delete(unpub_filepath)
            rebuild_main_edl_entry.call(event_ts)
          end
    
          # If microphone, remove from GROUP logic
          if filename_to_source[unpub_filepath] == 'microphone'
            group_active_audios.delete_if { |a| a[:filename] == unpub_filepath }
          end
    
        #------------------------------------------------------------------------
        # AUDIO GROUP: Created / Updated / Destroyed
        #------------------------------------------------------------------------
        when 'AudioGroupCreatedEvent'
          group_id = event.at_xpath('groupId')&.text
          next unless group_id
    
          audio_groups_edl[group_id] = [
            { timestamp: 0, audios: [] }
          ]
          senders = event.at_xpath('senders')&.text&.split(',') || []
          build_group_edl_entry.call(group_id, event_ts, senders)
    
          # Mark each user in "senders" as belonging to this group
          # => remove that user's microphone track(s) from main if they are active
          changed = false
          senders.each do |uid|
            old_count = user_in_groups[uid].size
            user_in_groups[uid].add(group_id)
            # If user just went from 0 groups => remove the mic track(s) from main
            if old_count == 0
              before = main_active_filenames.size
              main_active_filenames.delete_if do |fn|
                filename_to_user_id[fn] == uid && filename_to_source[fn] == 'microphone'
              end
              changed = true if main_active_filenames.size < before
            end
          end
          rebuild_main_edl_entry.call(event_ts) if changed
    
        when 'AudioGroupUpdatedEvent'
          group_id = event.at_xpath('groupId')&.text
          next unless group_id
    
          senders = event.at_xpath('senders')&.text&.split(',') || []
          build_group_edl_entry.call(group_id, event_ts, senders)
    
          # We interpret "senders" as the complete new set of users in group_id
          current_members = user_in_groups.select { |_, grp_set| grp_set.include?(group_id) }.keys
    
          leaving_users  = current_members - senders
          joining_users  = senders - current_members
    
          # 1) Remove group_id from each leaving user
          leaving_users.each do |uid|
            user_in_groups[uid].delete(group_id)
            # If user now has 0 groups, re-add that user's mic tracks to main if they are still active
            if user_in_groups[uid].empty?
              main_audios.each_key do |fn|
                if filename_to_user_id[fn] == uid && filename_to_source[fn] == 'microphone'
                  # Only re-add if it's not already in main_active_filenames
                  unless main_active_filenames.include?(fn)
                    main_active_filenames << fn
                  end
                end
              end
              rebuild_main_edl_entry.call(event_ts)
            end
          end
    
          # 2) Add group_id for each joining user
          joining_users.each do |uid|
            old_count = user_in_groups[uid].size
            user_in_groups[uid].add(group_id)
            # If user was in 0 groups => new group => remove mic track(s) from main
            if old_count == 0
              main_active_filenames.delete_if do |fn|
                filename_to_user_id[fn] == uid && filename_to_source[fn] == 'microphone'
              end
              rebuild_main_edl_entry.call(event_ts)
            end
          end
    
        when 'AudioGroupDestroyedEvent'
          group_id = event.at_xpath('groupId')&.text
          next unless group_id
    
          # Mark group as ended at event_ts with silence
          audio_groups_edl[group_id] << {
            timestamp: event_ts,
            audios:    []
          }
    
          # Now remove group_id from all users who had it
          current_members = user_in_groups.select { |_, grp_set| grp_set.include?(group_id) }.keys
          current_members.each do |uid|
            user_in_groups[uid].delete(group_id)
            # If user now has 0 groups, re-add any mic tracks to main
            if user_in_groups[uid].empty?
              main_audios.each_key do |fn|
                if filename_to_user_id[fn] == uid && filename_to_source[fn] == 'microphone'
                  unless main_active_filenames.include?(fn)
                    main_active_filenames << fn
                  end
                end
              end
              rebuild_main_edl_entry.call(event_ts)
            end
          end
    
        else
          # Ignore other events
          next
        end
      end

      # Append final silence entry to both main_audio_edl and each group’s EDL
      main_audio_edl << {
        timestamp: final_timestamp - initial_timestamp,
        audios:    []
      }
    
      audio_groups_edl.each_value do |group_edl|
        group_edl << {
          timestamp: final_timestamp - initial_timestamp,
          audios:    []
        }
      end

      # Return both EDLs
      return [main_audio_edl, audio_groups_edl]
    end

    def self.create_deskshare_audio_edl(events, deskshare_dir)
      audio_edl = []

      initial_timestamp = BigBlueButton::Events.first_event_timestamp(events)
      final_timestamp = BigBlueButton::Events.last_event_timestamp(events)
      filename = ""

      # Initially start with silence
      audio_edl << {
        :timestamp => 0,
        :audios => []
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
              :audios => [{ :filename => filename, :timestamp => 0 }]
            }
          when 'StopWebRTCDesktopShareEvent'
            if audio_edl.last.dig(:audios, 0, :filename) == filename
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
                :audios => []
              }
            end
          end
        else
          BigBlueButton.logger.debug " Screenshare without audio, ignoring..."
        end
      end

      audio_edl << {
        :timestamp => final_timestamp - initial_timestamp,
        :audios => []
      }

      return audio_edl
    end

  end
end
