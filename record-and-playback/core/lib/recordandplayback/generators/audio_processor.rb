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

require File.expand_path('../../edl', __FILE__)

module BigBlueButton
  class AudioProcessor

    @audio_file = nil;

    # Process the raw recorded audio to ogg file.
    #   archive_dir - directory location of the raw archives. Assumes there is audio file and events.xml present.
    #   file_basename - the file name of the audio output. '.webm' and '.ogg' will be added
    #
    def self.process(archive_dir, file_basename)
      BigBlueButton.logger.info("AudioProcessor.process: Processing audio...")

      events_xml = "#{archive_dir}/events.xml"
      events = Nokogiri::XML(File.open(events_xml))

      audio_edl = BigBlueButton::AudioEvents.create_audio_edl(
                      events, archive_dir)
      BigBlueButton::EDL::Audio.dump(audio_edl)

      BigBlueButton.logger.info("Applying recording start stop events:")
      start_time = BigBlueButton::Events.first_event_timestamp(events)
      end_time = BigBlueButton::Events.last_event_timestamp(events)
      audio_edl = BigBlueButton::Events.edl_match_recording_marks_audio(
                      audio_edl, events, start_time, end_time)
      BigBlueButton::EDL::Audio.dump(audio_edl)

      target_dir = File.dirname(file_basename)

      # getting users audio...
      @audio_file = BigBlueButton::EDL::Audio.render(
        audio_edl, File.join(target_dir, 'recording'))

      # and mixing it with deskshare audio	
      deskshare_dir = "#{archive_dir}/deskshare"
      if BigBlueButton::Events.screenshare_has_audio?(events, deskshare_dir)
        BigBlueButton.logger.info("AudioProcessor.process: processing Deskshare audio...")	

        mixed_dir = "#{archive_dir}/mixed"

        deskshare_audio_edl = BigBlueButton::AudioEvents.create_deskshare_audio_edl(events, deskshare_dir)
        BigBlueButton::EDL::Audio.dump(deskshare_audio_edl)	

        BigBlueButton.logger.info "Applying recording start/stop events to Deskshare audio"
        deskshare_audio_edl = BigBlueButton::Events.edl_match_recording_marks_audio(
          deskshare_audio_edl, events, start_time, end_time)
        BigBlueButton.logger.debug "Trimmed Deskshare Audio EDL:"
        BigBlueButton::EDL::Audio.dump(deskshare_audio_edl)

        audio_inputs = []	
        audio_inputs << @audio_file	
        audio_inputs << BigBlueButton::EDL::Audio.render(deskshare_audio_edl, deskshare_dir)	

        @audio_file = BigBlueButton::EDL::Audio.mixer(audio_inputs, mixed_dir)	
      else
        BigBlueButton.logger.info("AudioProcessor.process: no Deskshare audio to process.")	
      end

      ogg_format = {
        :extension => 'ogg',
        :parameters => [ [ '-c:a', 'copy', '-f', 'ogg' ] ]
      }
      BigBlueButton::EDL.encode(@audio_file, nil, ogg_format, file_basename)

      webm_format = {
        :extension => 'webm',
        :parameters => [ [ '-c:a', 'copy', '-f', 'webm' ] ],
        :postprocess => [ [ 'mkclean', '--quiet', ':input', ':output' ] ]
      }
      BigBlueButton::EDL.encode(@audio_file, nil, webm_format, file_basename)
    end

    def self.process_with_audio_groups(archive_dir, file_basename, include_groups)
      BigBlueButton.logger.info("AudioProcessor.process_all_audio: Processing main audio and audio groups...")

      events_xml = "#{archive_dir}/events.xml"
      events = Nokogiri::XML(File.open(events_xml))
    
      # Generate both MAIN audio EDL and AUDIO GROUP EDLs
      main_audio_edl, audio_groups_edl = BigBlueButton::AudioEvents.create_audio_edl_with_groups(events, archive_dir)
    
      # Dump main EDL for debugging
      BigBlueButton.logger.info("Main Audio EDL before trimming:")
      BigBlueButton::EDL::Audio.dump(main_audio_edl)
    
      # Apply start/stop trimming to main EDL
      start_time = BigBlueButton::Events.first_event_timestamp(events)
      end_time   = BigBlueButton::Events.last_event_timestamp(events)
      main_audio_edl = BigBlueButton::Events.edl_match_recording_marks_audio(
                          main_audio_edl, events, start_time, end_time)
      BigBlueButton.logger.info("Main Audio EDL after trimming:")
      BigBlueButton::EDL::Audio.dump(main_audio_edl)
    
      # Render the main audio to a file
      target_dir = File.dirname(file_basename)
      BigBlueButton.logger.info("Rendering main audio timeline...")
      main_audio_file = BigBlueButton::EDL::Audio.render(
        main_audio_edl,
        File.join(target_dir, 'recording')  # e.g. base name for the mix
      )
    
      # Encode main audio into OGG and WEBM
      ogg_format = {
        extension:  'ogg',
        parameters: [ [ '-c:a', 'copy', '-f', 'ogg' ] ]
      }
      BigBlueButton::EDL.encode(main_audio_file, nil, ogg_format, file_basename)
    
      webm_format = {
        extension:  'webm',
        parameters: [ [ '-c:a', 'copy', '-f', 'webm' ] ],
        postprocess: [ [ 'mkclean', '--quiet', ':input', ':output' ] ]
      }
      BigBlueButton::EDL.encode(main_audio_file, nil, webm_format, file_basename)
      @audio_file = main_audio_file	
    
      #-----------------------------------------------------------------------
      # Process AUDIO GROUPS
      #-----------------------------------------------------------------------
      if include_groups
        BigBlueButton.logger.info("Processing audio groups...")
        group_results = {}
        if audio_groups_edl.empty?
          BigBlueButton.logger.info("No audio groups to process.")
        else
          audio_groups_edl.each do |group_id, group_edl|
            BigBlueButton.logger.info("Printing EDL of group #{group_id}:")
            BigBlueButton::EDL::Audio.dump(group_edl)
      
            BigBlueButton.logger.info("Applying recording start stop events for group #{group_id}:")
            trimmed_group_edl = BigBlueButton::Events.edl_match_recording_marks_audio(
              group_edl, events, start_time, end_time
            )
            BigBlueButton::EDL::Audio.dump(trimmed_group_edl)
      
            # Render each group's audio to a distinct file
            output_basename = File.join(target_dir, "audio_group_#{group_id.gsub('|','_')}")
            group_audio_file = BigBlueButton::EDL::Audio.render(trimmed_group_edl, output_basename)
            BigBlueButton.logger.info("Group #{group_id} audio file generated at: #{group_audio_file}")
      
            # Encode group audio only to OGG
            BigBlueButton::EDL.encode(
              group_audio_file,
              nil,
              {
                extension:  'ogg',
                parameters: [ [ '-c:a', 'copy', '-f', 'ogg' ] ]
              },
              output_basename
            )
      
            # Store the final group filename in results
            group_results[group_id] = File.basename(group_audio_file)
          end
        end
        group_results
      else
        BigBlueButton.logger.info("Audio groups processing disabled.")
      end
    end

    def self.get_processed_audio_file(archive_dir, file_basename)
      BigBlueButton.logger.info("AudioProcessor.get_processed_audio_file")

      if(@audio_file == nil)
        BigBlueButton.logger.info("AudioProcessor.get_processed_audio_file: audio_file is null. Did you forget to call the process method before this? Processing...")
        process(archive_dir,file_basename)
      end

      return @audio_file
    end
  end
end
