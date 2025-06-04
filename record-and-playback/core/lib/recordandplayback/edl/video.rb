# encoding: UTF-8

# BigBlueButton open source conferencing system - http://www.bigbluebutton.org/
#
# Copyright (c) 2013 BigBlueButton Inc. and by respective authors.
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

require 'json'
require 'set'
require 'shellwords'
require_relative './media_utils'

module BigBlueButton
  module EDL
    module Video
      FFMPEG_WF_CODEC = 'libx264'
      FFMPEG_WF_ARGS = [
        '-codec', FFMPEG_WF_CODEC.to_s, '-preset', 'veryfast', '-crf', '30',
        '-x264opts', 'stitchable=1', '-force_key_frames', 'expr:gte(t,n_forced*10)', '-pix_fmt', 'yuv420p',
      ]
      WF_EXT = 'mp4'
      # Max PTS gap in ms to trigger video resampling
      MAX_GAP_FOR_RESAMPLE_MS = 60_000 # 1 minute

      def self.background_color
        '#202020'
        # debug pro tip: randomize background color
        # "\##{Random.bytes(3).unpack1('H*')}"
      end

      def self.dump(edl)
        BigBlueButton.logger.debug "EDL Dump (#{edl.length} entries):"
        edl.each do |entry|
          BigBlueButton.logger.debug "---"
          BigBlueButton.logger.debug "  Timestamp: #{entry[:timestamp]}"
          BigBlueButton.logger.debug "  Video Areas:"
          entry[:areas].each do |name, videos|
            BigBlueButton.logger.debug "    #{name}"
            videos.each do |video|
              BigBlueButton.logger.debug "      #{video[:filename]} at #{video[:timestamp]} (original duration: #{video[:original_duration]}, presenter? #{video[:presenter]}, floor timestamp: #{video[:floor_timestamp]}, name: #{video[:name]})"
            end
          end
        end
      end

      def self.merge(*edls)
        entries_i = Array.new(edls.length, 0)
        done = Array.new(edls.length, false)
        merged_edl = [ { :timestamp => 0, :areas => {} } ]

        while !done.all?
          # Figure out what the next entry in each edl is
          entries = []
          entries_i.each_with_index do |entry, edl|
            entries << edls[edl][entry]
          end

          # Find the next entry - the one with the lowest timestamp
          next_edl = nil
          next_entry = nil
          entries.each_with_index do |entry, edl|
            if entry
              if !next_entry or entry[:timestamp] < next_entry[:timestamp]
                next_edl = edl
                next_entry = entry
              end
            end
          end

          # To calculate differences, need the previous entry from the same edl
          prev_entry = nil
          if entries_i[next_edl] > 0
            prev_entry = edls[next_edl][entries_i[next_edl] - 1]
          end

          # Find new videos that were added
          add_areas = {}
          if prev_entry
            next_entry[:areas].each do |area, videos|
              add_areas[area] = []
              if !prev_entry[:areas][area]
                add_areas[area] = videos
              else
                videos.each do |video|
                  if !prev_entry[:areas][area].find { |v| v[:filename] == video[:filename] }
                    add_areas[area] << video
                  end
                end
              end
            end
          else
            add_areas = next_entry[:areas]
          end

          # Find videos that were removed
          del_areas = {}
          if prev_entry
            prev_entry[:areas].each do |area, videos|
              del_areas[area] = []
              if !next_entry[:areas][area]
                del_areas[area] = videos
              else
                videos.each do |video|
                  if !next_entry[:areas][area].find { |v| v[:filename] == video[:filename] }
                    del_areas[area] << video
                  end
                end
              end
            end
          end

          # Determine whether to create a new entry or edit the previous one
          merged_entry = { :timestamp => next_entry[:timestamp], :areas => {} }
          last_entry = merged_edl.last
          if last_entry[:timestamp] == next_entry[:timestamp]
            # Edit the existing entry
            merged_entry = last_entry
          else
            # Create a new entry
            merged_entry = { :timestamp => next_entry[:timestamp], :areas => {} }
            merged_edl << merged_entry
            # Have to copy videos from the last entry into the new entry, updating timestamps
            last_entry[:areas].each do |area, videos|
              merged_entry[:areas][area] = videos.map do |video|
                video.merge({
                  :timestamp => video[:timestamp] + merged_entry[:timestamp] - last_entry[:timestamp]
                })
              end
            end
          end

          # Remove deleted videos
          del_areas.each do |area, videos|
            merged_entry[:areas][area] = merged_entry[:areas][area].reject do |video|
              videos.find { |v| v[:filename] == video[:filename] }
            end
          end
          # Add new videos
          add_areas.each do |area, videos|
            if !merged_entry[:areas][area]
              merged_entry[:areas][area] = videos
            else
              merged_entry[:areas][area] += videos
            end
          end

          # Pull in timestamps from the next entry to respect edit cuts
          next_entry[:areas].each do |area, videos|
            videos.each do |video|
              merged_video = merged_entry[:areas][area].find do |v|
                v[:filename] == video[:filename]
              end
              if !merged_video.nil?
                # it's no longer enough to just copy over timestamp, but need to bring all properties
                merged_video.merge!(video)
              end
            end
          end

          entries_i[next_edl] += 1
          if entries_i[next_edl] >= edls[next_edl].length
            done[next_edl] = true
          end
        end

        merged_edl
      end

      def self.sort_webcam_area(webcam_entries)
        webcam_entries.sort_by { |entry| [
          entry[:presenter] ? 0 : 1,
          -entry[:floor_timestamp],
          entry[:join_timestamp]
        ] }
      end

      def self.sort(edl)
        BigBlueButton.logger.debug "EDL Sort"
        edl.each do |edl_entry|
          edl_entry[:areas][:webcam] = sort_webcam_area(edl_entry[:areas][:webcam])
        end
      end

      # Edit the EDL to make sure that every cut has a minimum length to ensure processing will work properly
      def self.enforce_cut_lengths(edl, framerate)
        # Set the minimum cut length to 2 frames long
        # This can range from 83ms for 24fps video (video format), up to 400ms (presentation format deskshare)
        min_cut_len = (1000 / framerate * 2).round

        # Iterate through the edl entries from end to just after the start
        (edl.length - 1).downto(1).each do |i|
          duration = edl[i][:timestamp] - edl[i - 1][:timestamp]
          # If the cut that *ends* at EDL entry i is less than the minimum cut length
          next unless duration < min_cut_len

          # Then delete edl entry i - 1 from the list
          BigBlueButton.logger.debug("Dropping EDL entry index #{i - 1} (#{duration} < #{min_cut_len})")
          edl.delete_at(i - 1)
          # On the next iteration through the loop, we'll be re-checking from the same end point, but a new start
        end

        # What if the first cut got deleted?
        if edl[0][:timestamp] != 0
          # Need to reset the first cut to start at timestamp 0
          BigBlueButton.logger.debug('Resetting timestamp of first EDL entry to 0')
          offset = edl[0][:timestamp]
          edl[0][:timestamp] = 0
          # And offset the start times of every video to compensate
          edl[0][:areas].each_value do |videos|
            videos.each do |video|
              video[:timestamp] -= offset # This might become negative, that's ok.
            end
          end
        end

        # What if all of the cuts got deleted?
        if edl.length == 1
          BigBlueButton.logger.debug('EDL contains no cuts - enforcing minimum length')
          # Add a new end point at the minimum cut length
          edl << { timestamp: min_cut_len, areas: {} }
        end

        nil
      end

      def self.render(edl, layout, output_basename)
        videoinfo = {}

        corrupt_videos = Set.new
        try_remux_videos = Set.new

        BigBlueButton.logger.info "Pre-processing EDL"
        enforce_cut_lengths(edl, layout[:framerate])

        for i in 0...(edl.length - 1)
          # The render scripts need this to calculate cut lengths
          edl[i][:next_timestamp] = edl[i+1][:timestamp]
          # Have to fetch information about all the input video files,
          # so collect them.
          edl[i][:areas].each do |name, videos|
            videos.each do |video|
              videoinfo[video[:filename]] = {}
            end
          end
        end

        BigBlueButton.logger.info "Reading source video information"
        videoinfo.keys.each do |videofile|
          BigBlueButton.logger.debug "  #{videofile}"
          info = video_info(videofile)
          if !info[:video]
            BigBlueButton.logger.warn "    This video file (#{File.basename(videofile)}) is corrupted! It will be removed from the output."
            corrupt_videos << videofile
            next
          elsif info[:duration] == 0
            BigBlueButton.logger.warn "    This video file (#{File.basename(videofile)}) has zero duration! It will be removed from the output."
            corrupt_videos << videofile
            next
          end

          videoinfo[videofile] = info

          BigBlueButton.logger.debug "    width: #{info[:width]}, height: #{info[:height]}, duration: #{info[:duration]}, start_time: #{info[:start_time]}"
          if info[:video][:deskshare_timestamp_bug]
            BigBlueButton.logger.debug("    has early 1.1 deskshare timestamp bug")
          elsif info[:format][:format_name] == 'flv' and info[:start_time] > 1
            BigBlueButton.logger.debug("    has large start time, needs remuxing")
            try_remux_videos << videofile
          end

          # Try decoding a frame to detect some types of problems
          unless test_video_decode(videofile)
            BigBlueButton.logger.warn("    Failed to run test decode; will attempt to remux")
            try_remux_videos << videofile
          end
        end

        if try_remux_videos.length > 0
          BigBlueButton.logger.info("Attempting remux of videos with problems")
          remuxdir = File.join(File.dirname(output_basename), "remux")
          FileUtils.mkdir_p(remuxdir)
          try_remux_videos.each do |videofile|
            BigBlueButton.logger.info("  #{File.basename(videofile)}")
            newvideofile = File.join(remuxdir, "#{File.basename(videofile, '.*')}.nut")

            unless File.exist?(newvideofile)
              ffmpeg_cmd = [*FFMPEG, '-i', videofile, '-c', 'copy', newvideofile]
              exitstatus = BigBlueButton.execute(ffmpeg_cmd, false)
              unless exitstatus.success?
                BigBlueButton.logger.warn("    Remux command failed, input file is unusable")
                corrupt_videos << videofile
                next
              end
            end

            info = video_info(newvideofile)
            if !info[:video] || !test_video_decode(newvideofile)
              BigBlueButton.logger.warn("    Result of remux is corrupt, not using it.")
              corrupt_videos << videofile
              next
            end

            BigBlueButton.logger.debug "    width: #{info[:width]}, height: #{info[:height]}, duration: #{info[:duration]}, start_time: #{info[:start_time]}"
            videoinfo[newvideofile] = info

            # Update the filename in the EDL
            edl.each do |event|
              event[:areas].each do |area, videos|
                videos.each do |video|
                  if video[:filename] == videofile
                    video[:filename] = newvideofile
                  end
                end
              end
            end
          end
        end

        # Identify and resample videos with large PTS gaps
        videos_to_resample_due_to_gaps = {}
        videoinfo.keys.each do |videofile|
          next if corrupt_videos.include?(videofile) # Skip already corrupt videos

          # Ensure videofile is not already a resampled one from a previous remux step if names overlap
          next if videofile.include?("_resampled.") || videofile.include?(".nut")

          gap_details = BigBlueButton::EDL::MediaUtils.has_large_pts_gaps?(videofile, MAX_GAP_FOR_RESAMPLE_MS, 'v')
          if gap_details
            BigBlueButton.logger.info "Video '#{File.basename(videofile)}' identified with large PTS gap between #{gap_details[0].round(3)}s and #{gap_details[1].round(3)}s. Marking for segmented resampling."
            videos_to_resample_due_to_gaps[videofile] = gap_details
          end
        end

        if videos_to_resample_due_to_gaps.any?
          BigBlueButton.logger.info "Resampling #{videos_to_resample_due_to_gaps.length} video(s) with large PTS gaps (segmented approach)."
          resampled_videos_dir = File.join(File.dirname(output_basename), "resampled_videos_segmented")
          FileUtils.mkdir_p(resampled_videos_dir)
          
          filename_update_map_gaps = resample_video_files(videos_to_resample_due_to_gaps, resampled_videos_dir, videoinfo)

          if filename_update_map_gaps.any?
            BigBlueButton.logger.info "Updating EDL and video information for segment-resampled videos."
            edl.each do |entry|
              entry[:areas].each_value do |videos_in_area|
                videos_in_area.each do |video_data|
                  if filename_update_map_gaps.key?(video_data[:filename])
                    video_data[:filename] = filename_update_map_gaps[video_data[:filename]]
                  end
                end
              end
            end

            filename_update_map_gaps.each do |original_filename, new_filename|
              info = video_info(new_filename)
              if !info[:video] || info[:duration] == 0
                BigBlueButton.logger.error "Resampled video file #{new_filename} is corrupt or invalid. Original: #{original_filename}. This may cause issues."
                corrupt_videos << new_filename # Mark the new file as corrupt
                videoinfo.delete(original_filename) if videoinfo.key?(original_filename)
              else
                BigBlueButton.logger.debug "Successfully resampled and got info for #{new_filename}. Duration: #{info[:duration]}"
                videoinfo[new_filename] = info
                videoinfo.delete(original_filename) if videoinfo.key?(original_filename)
              end
            end
          end
        end

        if corrupt_videos.length > 0
          BigBlueButton.logger.info "Removing corrupt video files from EDL"
          edl.each do |event|
            event[:areas].each do |area, videos|
              videos.delete_if { |video| corrupt_videos.include?(video[:filename]) }
            end
          end
        end

        # limit number of videos according to layout limit
        for i in 0...(edl.length - 1)
          cut = edl[i]
          layout[:areas].each do |layout_area|
            next if cut[:areas][layout_area[:name]].nil?

            if ! layout_area[:limit].nil? and cut[:areas][layout_area[:name]].length > layout_area[:limit]
              cut[:areas][layout_area[:name]] = cut[:areas][layout_area[:name]].slice(0, layout_area[:limit])
            end
          end
        end

        BigBlueButton.logger.info "Video EDL after pre-processing:"
        dump(edl)

        BigBlueButton.logger.info "Compositing cuts"
        render = "#{output_basename}.#{WF_EXT}"
        concat = []
        for i in 0...(edl.length - 1)
          segment = "#{output_basename}_#{i}.#{WF_EXT}"
          composite_cut(segment, edl[i], layout, videoinfo)
          concat << segment
        end

        concat_file = "#{output_basename}.txt"
        File.open(concat_file, 'w') do |outio|
          concat.each do |segment|
            outio.write("file #{segment}\n")
          end
        end

        ffmpeg_cmd = [*FFMPEG, '-safe', '0', '-f', 'concat', '-i', concat_file , '-c', 'copy', render]
        exitstatus = BigBlueButton.exec_ret(*ffmpeg_cmd)
        raise "ffmpeg failed, exit code #{exitstatus}" if exitstatus != 0

        concat.each do |segment|
          File.delete(segment)
        end

        return render
      end

      # The methods below are for private use

      # Determines segments for processing based on PTS gaps and keyframes.
      # Returns an array of hashes: [{start_pts: float, end_pts: float, action: :copy | :recode}, ...]
      def self.get_all_processing_segments(filename, max_gap_ms, video_total_duration_s, video_info_entry)
        times_data = get_packet_and_keyframe_times(filename)
        return [{ start_pts: 0.0, end_pts: video_total_duration_s, action: :copy }] if times_data.nil? # Fallback to full copy if data unavailable

        all_pts_times = times_data[:pts_times]
        keyframe_pts = times_data[:keyframe_pts_times]

        if all_pts_times.empty?
          BigBlueButton.logger.warn "No PTS times found for '#{File.basename(filename)}'. Assuming no gaps and full copy."
          return [{ start_pts: 0.0, end_pts: video_total_duration_s, action: :copy }]
        end

        # Add 0.0 and duration to keyframes if not present, to simplify segment boundary logic
        keyframe_pts.unshift(0.0) unless keyframe_pts.include?(0.0) || keyframe_pts.any? { |kf| kf < 0.01 } # Add 0 if no early keyframe
        keyframe_pts.push(video_total_duration_s) unless keyframe_pts.include?(video_total_duration_s) || keyframe_pts.any? { |kf| (kf - video_total_duration_s).abs < 0.01 }
        keyframe_pts.sort!.uniq!

        max_gap_seconds = max_gap_ms / 1000.0
        recode_intervals = []

        BigBlueButton.logger.debug "Analyzing PTS gaps for '#{File.basename(filename)}' (max_gap: #{max_gap_seconds.round(3)}s)"
        previous_pts = nil
        all_pts_times.each do |current_pts|
          if previous_pts
            gap = current_pts - previous_pts
            if gap > max_gap_seconds
              BigBlueButton.logger.info "Large PTS gap (#{gap.round(3)}s) found in '#{File.basename(filename)}' between #{previous_pts.round(3)}s and #{current_pts.round(3)}s."
              
              # Find keyframe at or before previous_pts (gap_start)
              kf_before_gap = keyframe_pts.select { |kf| kf <= previous_pts + 0.001 }.max || 0.0 
              # Find keyframe at or after current_pts (gap_end)
              kf_after_gap = keyframe_pts.select { |kf| kf >= current_pts - 0.001 }.min || video_total_duration_s

              # Ensure kf_after_gap is greater than kf_before_gap for a valid interval
              if kf_after_gap > kf_before_gap + 0.01 # Min duration for re-encode segment
                recode_intervals << { start: kf_before_gap, end: kf_after_gap }
                BigBlueButton.logger.info "  Gap will be handled by re-encoding segment from keyframe #{kf_before_gap.round(3)}s to keyframe #{kf_after_gap.round(3)}s."
              else
                BigBlueButton.logger.warn "  Could not define a valid keyframe interval for gap at #{previous_pts.round(3)}s; kf_before=#{kf_before_gap.round(3)}, kf_after=#{kf_after_gap.round(3)}. Gap might persist."
              end
            end
          end
          previous_pts = current_pts
        end

        # Merge overlapping/adjacent recode_intervals
        recode_intervals.sort_by! { |r| r[:start] }
        merged_recode_intervals = []
        recode_intervals.each do |current_interval|
          if merged_recode_intervals.empty? || current_interval[:start] >= merged_recode_intervals.last[:end] - 0.001 # Allow tiny overlaps due to float precision
            merged_recode_intervals << current_interval
          else
            merged_recode_intervals.last[:end] = [merged_recode_intervals.last[:end], current_interval[:end]].max
          end
        end
        
        segments = []
        last_processed_pts = 0.0
        merged_recode_intervals.each do |interval|
          if interval[:start] > last_processed_pts + 0.01 # Min duration for copy segment
            segments << { start_pts: last_processed_pts, end_pts: interval[:start], action: :copy }
          end
          segments << { start_pts: interval[:start], end_pts: interval[:end], action: :recode }
          last_processed_pts = interval[:end]
        end

        if last_processed_pts < video_total_duration_s - 0.01 # Min duration for final copy segment
          segments << { start_pts: last_processed_pts, end_pts: video_total_duration_s, action: :copy }
        end
        
        if segments.empty? && video_total_duration_s > 0.01
           BigBlueButton.logger.info "No recode intervals for '#{File.basename(filename)}', creating a single copy segment."
           segments << { start_pts: 0.0, end_pts: video_total_duration_s, action: :copy }
        elsif segments.empty? && video_total_duration_s <= 0.01
           BigBlueButton.logger.warn "Video '#{File.basename(filename)}' has zero or negligible duration. No segments generated."
        end

        BigBlueButton.logger.debug "Processing segments for '#{File.basename(filename)}': #{segments.inspect}"
        segments
      end

      # Resamples video files by identifying all large PTS gaps, cutting at surrounding keyframes,
      # re-encoding gappy segments (by replacing with blank video), and stream-copying stable segments.
      # Outputs an MKV file.
      def self.resample_video_files(files_and_gap_info_map, target_directory, videoinfo_h)
        filename_update_map = {}
        intermediate_format = 'webm' # Intermediate parts can remain webm

        files_and_gap_info_map.each do |original_filename, _first_gap_info_ignored| # First gap info is ignored, we find all gaps
          original_basename = File.basename(original_filename, '.*')
          parts_dir = File.join(target_directory, "#{original_basename}_parts")
          FileUtils.mkdir_p(parts_dir)

          original_video_codec_info = videoinfo_h[original_filename]&.dig(:video, :codec_name)
          unless original_video_codec_info
            BigBlueButton.logger.error "Could not determine original video codec for #{original_filename}. Skipping segmented resampling."
            FileUtils.remove_entry_secure(parts_dir) if Dir.exist?(parts_dir)
            next
          end
          original_total_duration_s = videoinfo_h[original_filename][:duration] / 1000.0

          output_ext = 'webm' # Reverted from 'mkv' back to 'webm'
          final_resampled_filename = File.join(target_directory, "#{original_basename}_segmented_resampled.#{output_ext}")
          
          BigBlueButton.logger.info "Segmented resampling for '#{original_filename}' (codec: #{original_video_codec_info}, duration: #{original_total_duration_s.round(3)}s). Output: '#{final_resampled_filename}'"

          processing_segments = get_all_processing_segments(original_filename, MAX_GAP_FOR_RESAMPLE_MS, original_total_duration_s, videoinfo_h[original_filename])

          if processing_segments.empty?
            BigBlueButton.logger.warn "No processing segments generated for '#{original_filename}'. Skipping segmented resampling for this file."
            FileUtils.remove_entry_secure(parts_dir) if Dir.exist?(parts_dir)
            next
          end
          
          # If only one copy segment covering the whole video, it's like a remux.
          # This can happen if no significant gaps are found or keyframes don't allow isolation.
          if processing_segments.length == 1 && processing_segments.first[:action] == :copy && processing_segments.first[:start_pts] < 0.01 && (processing_segments.first[:end_pts] - original_total_duration_s).abs < 0.01
             BigBlueButton.logger.info "No gaps requiring re-encoding found for '#{original_filename}' based on keyframes. Will perform a simple copy/remux."
             # This will be handled by the loop below creating one copy part.
          end

          parts_to_concat = []
          overall_success = true

          processing_segments.each_with_index do |segment, index|
            part_start_pts = segment[:start_pts]
            part_end_pts = segment[:end_pts]
            action = segment[:action]
            part_duration = part_end_pts - part_start_pts

            if part_duration <= 0.01 # Skip negligible/zero duration segments
              BigBlueButton.logger.debug "Skipping segment ##{index+1} for '#{original_filename}' due to zero/negligible duration (#{part_duration.round(3)}s)."
              next
            end

            part_path = File.join(parts_dir, "#{original_basename}_part#{index + 1}.#{intermediate_format}")
            
            if action == :recode
              # Generate a blank video segment for the duration of the gap.
              original_info = videoinfo_h[original_filename]
              width = original_info[:width]
              height = original_info[:height]
              framerate = 25 

              color_source_spec = "color=c=#{self.background_color}:s=#{width}x#{height}:r=#{framerate}"

              cmd_part = [*FFMPEG, '-y', '-f', 'lavfi', '-i', color_source_spec, '-t', part_duration.to_s]
              cmd_part += ['-an'] # No audio for the blank video segment
              # Using typical VP8 parameters.
              cmd_part += ['-c:v', 'libvpx', '-crf', '30', '-b:v', '1M'] 
              BigBlueButton.logger.info "Creating Part ##{index + 1} (BLANK VIDEO from #{part_start_pts.round(3)}s to #{part_end_pts.round(3)}s, duration #{part_duration.round(3)}s) for '#{original_filename}'"
            else # :copy
              # Use -t with part_duration for copied segments.
              # Add -avoid_negative_ts make_zero for robust timestamp handling.
              cmd_part = [*FFMPEG, '-y', '-ss', part_start_pts.to_s, '-i', original_filename, '-t', part_duration.to_s]
              cmd_part += ['-c', 'copy', '-avoid_negative_ts', 'make_zero', '-reset_timestamps', '1']
              BigBlueButton.logger.info "Creating Part ##{index + 1} (COPY from #{part_start_pts.round(3)}s, duration #{part_duration.round(3)}s) for '#{original_filename}'"
            end
            cmd_part << part_path

            exit_status_part = BigBlueButton.exec_ret(*cmd_part)

            if exit_status_part == 0 && File.exist?(part_path) && File.size(part_path) > 0
              parts_to_concat << part_path
            else
              BigBlueButton.logger.error "Failed to create or empty Part ##{index + 1} (#{action}) for '#{original_filename}'. Segmented resampling failed for this file."
              overall_success = false
              break # Stop processing further parts for this file
            end
          end

          if overall_success && parts_to_concat.any?
            concat_list_path = File.join(parts_dir, "concat_list.txt")
            File.open(concat_list_path, 'w') do |f|
              parts_to_concat.each { |part_file| f.puts "file '#{File.absolute_path(part_file)}'" }
            end

            cmd_concat = [*FFMPEG, '-y', '-f', 'concat', '-safe', '0', '-i', concat_list_path,
                          '-c', 'copy', '-an',
                          final_resampled_filename]
            BigBlueButton.logger.debug "Concatenating #{parts_to_concat.length} parts for '#{original_filename}'"
            exit_status_concat = BigBlueButton.exec_ret(*cmd_concat)

            if exit_status_concat == 0 && File.exist?(final_resampled_filename)
              BigBlueButton.logger.info "Successfully segment-resampled '#{original_filename}' to '#{final_resampled_filename}'"
              filename_update_map[original_filename] = final_resampled_filename
            else
              BigBlueButton.logger.error "Concatenation failed for '#{original_filename}'. Segmented resampling failed. Check ffmpeg logs."
            end
          elsif overall_success && parts_to_concat.empty?
            BigBlueButton.logger.warn "No valid parts to concatenate for '#{original_filename}' after attempting segmented resampling (e.g., source too short or all parts failed/skipped)."
          elsif !overall_success
            BigBlueButton.logger.error "Segmented resampling process failed for '#{original_filename}' during part creation."
          end
          
          FileUtils.remove_entry_secure(parts_dir) if Dir.exist?(parts_dir)
        end
        filename_update_map
      end

      def self.video_info(filename)
        IO.popen([*FFPROBE, '-select_streams', 'v:0', '-count_frames', '-read_intervals', '%+#10', filename]) do |probe|
          info = nil
          begin
            info = JSON.parse(probe.read, :symbolize_names => true)
          rescue StandardError => e
            BigBlueButton.logger.warn("Couldn't parse video info: #{e}")
          end
          return {} if !info
          return {} if !info[:streams]
          return {} if !info[:format]

          info[:video] = info[:streams].find do |stream|
            stream[:codec_type] == 'video'
          end

          return {} if !info[:video]

          info[:width] = info[:video][:width].to_i
          info[:height] = info[:video][:height].to_i

          # Check for corrupt/undecodable video streams
          return {} if info[:video][:pix_fmt].nil?
          return {} if info[:width] == 0 or info[:height] == 0
          return {} if info[:video][:nb_read_frames].nil? || info[:video][:nb_read_frames] == 'N/A'

          info[:sample_aspect_ratio] = Rational(1, 1)
          if !info[:video][:sample_aspect_ratio].nil? and
              info[:video][:sample_aspect_ratio] != 'N/A'
            aspect_x, aspect_y = info[:video][:sample_aspect_ratio].split(':')
            aspect_x = aspect_x.to_i
            aspect_y = aspect_y.to_i
            if aspect_x != 0 and aspect_y != 0
              info[:sample_aspect_ratio] = Rational(aspect_x, aspect_y)
            end
          end

          info[:aspect_ratio] = Rational(info[:width], info[:height]) * info[:sample_aspect_ratio]

          if info[:format][:format_name] == 'flv' and info[:video][:codec_name] == 'h264'
            info[:video][:deskshare_timestamp_bug] = self.check_deskshare_timestamp_bug(filename)
          end

          # Convert the duration to milliseconds
          if !info[:format][:duration].nil? and
              info[:format][:duration] != 'N/A'
            info[:duration] = (info[:format][:duration].to_r * 1000).to_i
          else
            # For some reason, ffprobe has a hard time finding duration on some webm files, that's why a fallback is implemented
            # which actually process the whole video and figure out its final duration
            info[:duration] = self.fallback_video_duration(filename)
            BigBlueButton.logger.info "No duration found for #{File.basename(filename)} using ffprobe. Duration from ffmpeg: #{info[:duration]}ms"
          end

          info[:start_time] = (info[:format][:start_time].to_r * 1000).to_i
          info[:video][:start_time] = (info[:video][:start_time].to_r * 1000).to_i

          return info
        end
        {}
      end

      def self.fallback_video_duration(filename)
        output = `ffmpeg -i #{filename} -f null /dev/null 2>&1 | grep '^frame=' | sed 's/.* time=\\([^ ]*\\).*/\\1/g'`.strip
        if /^\d+:\d+:\d+.\d+$/.match output
          # process time in the format 00:00:24.60 (ffmpeg sexagesimal)
          duration_a = output.scan(/(\d+)/).map{ |num| num[0] }

          ( ( duration_a[0].to_i * 3600 + duration_a[1].to_i * 60 + duration_a[2].to_i + "0.#{duration_a[3]}".to_f ) * 1000 ).to_i
        else
          0
        end
      end

       # Try decoding a frame to detect some types of problems
       def self.test_video_decode(videofile)
        ffmpeg_cmd = [
          *FFMPEG,
          '-max_error_rate', '0',
          '-noaccurate_seek', '-ss', '0', '-i', videofile,
          '-map', '0:v:0', '-frames:v', '1', '-f', 'null', '-',
        ]
        exitstatus = BigBlueButton.execute(ffmpeg_cmd, false)
        exitstatus.success?
      end

      def self.check_deskshare_timestamp_bug(filename)
        IO.popen([*FFPROBE, '-select_streams', 'v:0', '-show_frames', '-read_intervals', '%+#10', filename]) do |probe|
          info = JSON.parse(probe.read, symbolize_names: true)
          return false if !info

          if info[:frames].nil? || info[:frames].empty?
            return false
          end

          # First frame in broken stream always has pts=1
          if info[:frames][0][:pkt_pts] != 1
            return false
          end

          # Remaining frames start at 200, and go up by exactly 200 each frame
          for i in 1...info[:frames].length
            if info[:frames][i][:pkt_pts] != i * 200
              return false
            end
          end

          return true
        end
      end

      def self.ms_to_s(timestamp)
        s = timestamp / 1000
        ms = timestamp % 1000
        "%d.%03d" % [s, ms]
      end

      def self.aspect_scale(old_width, old_height, new_width, new_height)
        if old_width.to_f / old_height > new_width.to_f / new_height
          new_height = (2 * (old_height.to_f * new_width / old_width / 2).round).to_i
        else
          new_width = (2 * (old_width.to_f * new_height / old_height / 2).round).to_i
        end
        [new_width, new_height]
      end

      def self.composite_cut(output, cut, layout, videoinfo)
        duration = cut[:next_timestamp] - cut[:timestamp]
        BigBlueButton.logger.info "  Cut start time #{cut[:timestamp]}, duration #{duration}"

        aux_ffmpeg_processes = {}
        ffmpeg_inputs = [
          {
            format: 'lavfi',
            filename: "color=c=#{background_color}:s=#{layout[:width]}x#{layout[:height]}:r=#{layout[:framerate]}"
          }
        ]
        ffmpeg_input_pipes = {}
        ffmpeg_filter = '[0]null'
        layout[:areas].each do |layout_area|
          area = cut[:areas][layout_area[:name]]
          next if area.nil?

          video_count = area.length
          BigBlueButton.logger.debug "  Laying out #{video_count} videos in #{layout_area[:name]}"
          next if video_count == 0

          tile_offset_x = layout_area[:x] # not used
          tile_offset_y = layout_area[:y] # not used
          border = layout_area[:border] || 0

          tiles_h = 0
          tiles_v = 0
          tile_width = 0
          tile_height = 0
          total_area = 0
          max_video_width = 0
          max_video_height = 0

          # Do an exhaustive search to maximize video areas
          for tmp_tiles_v in 1..video_count
            tmp_tiles_h = (video_count / tmp_tiles_v.to_f).ceil
            tmp_tile_width = (2 * (layout_area[:width].to_f / tmp_tiles_h / 2).floor).to_i - border * 2
            tmp_tile_height = (2 * (layout_area[:height].to_f / tmp_tiles_v / 2).floor).to_i - border * 2
            next if tmp_tile_width <= 0 or tmp_tile_height <= 0

            tmp_total_area = 0
            tmp_max_video_width = 0
            tmp_max_video_height = 0
            area.each do |video|
              video_width = videoinfo[video[:filename]][:aspect_ratio].numerator
              video_height = videoinfo[video[:filename]][:aspect_ratio].denominator
              scale_width, scale_height = aspect_scale(video_width, video_height, tmp_tile_width, tmp_tile_height)
              tmp_total_area += scale_width * scale_height
              tmp_max_video_width = [ tmp_max_video_width, scale_width ].max
              tmp_max_video_height = [ tmp_max_video_height, scale_height ].max
            end

            if tmp_total_area > total_area
              tiles_h = tmp_tiles_h
              tiles_v = tmp_tiles_v
              tile_width = tmp_tile_width
              tile_height = tmp_tile_height
              total_area = tmp_total_area
              max_video_width = tmp_max_video_width
              max_video_height = tmp_max_video_height
            end
          end

          tile_width = max_video_width + border * 2

          if layout_area[:name].to_s == "deskshare" or layout_area[:name].to_s == "presentation"
            tile_height = layout_area[:height]
          else
            tile_height = max_video_height + border * 2
          end

          tiles_pad_x = ( ( layout_area[:width] - tile_width * tiles_h ).to_f / 2 ).floor.to_i
          tiles_pad_y = ( ( layout_area[:height] - tile_height * tiles_v ).to_f / 2 ).floor.to_i

          tile_x = 0
          tile_y = 0

          BigBlueButton.logger.debug "    Tiling in a #{tiles_h}x#{tiles_v} grid"

          ffmpeg_filter << "[#{layout_area[:name]}_in];"

          area.each do |video|
            this_videoinfo = videoinfo[video[:filename]]
            BigBlueButton.logger.debug "    tile location (#{tile_x}, #{tile_y})"
            video_width = this_videoinfo[:aspect_ratio].numerator
            video_height = this_videoinfo[:aspect_ratio].denominator
            BigBlueButton.logger.debug "      original aspect: #{video_width}x#{video_height}"

            scale_width, scale_height = aspect_scale(video_width, video_height, tile_width, tile_height)
            BigBlueButton.logger.debug "      scaled size: #{scale_width}x#{scale_height}"

            seek = video[:timestamp]
            BigBlueButton.logger.debug("      start timestamp: #{seek}")
            seek_offset = this_videoinfo[:start_time]
            video_start_offset = this_videoinfo[:video][:start_time]
            BigBlueButton.logger.debug("      seek offset: #{seek_offset}, video start offset: #{video_start_offset}")
            BigBlueButton.logger.debug("      codec: #{this_videoinfo[:video][:codec_name].inspect}")
            BigBlueButton.logger.debug("      duration: #{this_videoinfo[:duration]}, original duration: #{video[:original_duration]}")

            # Desktop sharing videos in flashsv2 do not have regular
            # keyframes, so seeking in them doesn't really work.
            # To make processing more reliable, always decode them from the
            # start in each cut. (Slow!)
            seek = 0 if this_videoinfo[:video][:codec_name] == 'flashsv2'

            # Workaround early 1.1 deskshare timestamp bug
            # It resulted in video files that were too short. To workaround, we
            # assume that the framerate was constant throughout (it might not
            # actually be...) and scale the video length.
            scale = nil
            if !video[:original_duration].nil? and
                  this_videoinfo[:video][:deskshare_timestamp_bug]
              scale = video[:original_duration].to_f / this_videoinfo[:duration]
              # Rather than attempt to recalculate seek...
              seek = 0
              BigBlueButton.logger.debug("      Early 1.1 deskshare timestamp bug: scaling video length by #{scale}")
            end

            pad_name = "#{layout_area[:name]}_x#{tile_x}_y#{tile_y}"

            tile_x += 1
            if tile_x >= tiles_h
              tile_x = 0
              tile_y += 1
            end

            input_index = ffmpeg_inputs.length

            # If the seekpoint is at or after the end of the file, the filter chain will
            # have problems. Substitute in a blank video.
            if seek >= this_videoinfo[:duration]
              ffmpeg_inputs << {
                format: 'lavfi',
                filename: "color=c=#{background_color}:s=#{tile_width}x#{tile_height}:r=#{layout[:framerate]}"
              }
              ffmpeg_filter << "[#{input_index}]null[#{pad_name}];"
              next
            end

            # Apply the video start time offset to seek to the correct point.
            # Only actually apply the offset if we're already seeking so we
            # don't start seeking in a file where we've overridden the seek
            # behaviour.
            if seek > 0
              seek = seek + seek_offset
            end

            # Launch the ffmpeg process to use for this input to pre-process the video to constant video resolution
            # This has to be done in an external process, since if it's done in the same process, the entire filter
            # chain gets re-initialized on every resolution change, resulting in losing state on all stateful filters.
            ffmpeg_preprocess_log = "#{output}.#{pad_name}.log"
            ffmpeg_preprocess_read, ffmpeg_preprocess_write = IO.pipe

            # To reduce overhead, adjust the size of the fifo buffer larger
            # By default, Linux allows pipe sizes to be increased to 1MB by normal users.
            begin
              ffmpeg_preprocess_write.fcntl(Fcntl::F_SETPIPE_SZ, 1_048_576)
            rescue Errno::EPERM
              BigBlueButton.logger.warn('Unable to increase pipe size to 1MB')
            rescue NameError
              # Fcntl::F_SETPIPE_SZ isn't available on Ruby version older than 3.0
            end

            in_time = video[:timestamp] + seek_offset
            out_time = in_time + duration

            # Pre-filtering: scaling, padding, and extending.
            ffmpeg_preprocess_filter = String.new
            ffmpeg_preprocess_filter << '[0:v:0]'
            ffmpeg_preprocess_filter << "scale=w=#{tile_width - border * 2}:h=#{tile_height - border * 2}:force_original_aspect_ratio=decrease,"
            ffmpeg_preprocess_filter << "setsar=1,pad=w=#{tile_width}:h=#{tile_height}:x=-1:y=-1:color=#{background_color},"
            # The trim command combines its arguments - end at the timestamp but only if at least one frame has been output.
            ffmpeg_preprocess_filter << "trim=end=#{ms_to_s(out_time)}:end_frame=1"
            ffmpeg_preprocess_filter << '[out]'

            # Set up filters and inputs for video pre-processing ffmpeg command
            ffmpeg_preprocess_command = [
              'ffmpeg', '-y', '-v', 'warning', '-nostats', '-nostdin', '-max_error_rate', '1.0',
              # Add -fflags +discardcorrupt to try and discard corrupted packets.
              # Ensure input isn't misdetected as cfr, and frames prior to seek point run through filters.
              # Add -err_detect ignore_err to try and power through decoding errors, especially for VP8.
              #'-fflags', '+discardcorrupt', '-err_detect', 'ignore_err', '-vsync', 'vfr', '-noaccurate_seek',
              '-vsync', 'vfr', '-noaccurate_seek',
              '-ss', ms_to_s(seek).to_s, '-itsoffset', ms_to_s(seek).to_s, '-i', video[:filename],
              '-filter_complex', ffmpeg_preprocess_filter, '-map', '[out]',
              # Copy timebase from input instead of guessing based on framerate
              '-enc_time_base', '-1',
              '-c:v', 'rawvideo', '-f', 'nut', "pipe:#{ffmpeg_preprocess_write.fileno}",
            ]
            BigBlueButton.logger.info("Executing: #{Shellwords.join(ffmpeg_preprocess_command)}")
            ffmpeg_preprocess_pid = spawn(
              *ffmpeg_preprocess_command,
              err: [ffmpeg_preprocess_log, 'w'],
              ffmpeg_preprocess_write => ffmpeg_preprocess_write
            )
            ffmpeg_preprocess_write.close
            BigBlueButton.logger.debug("preprocessing ffmpeg command pid #{ffmpeg_preprocess_pid}")
            aux_ffmpeg_processes[ffmpeg_preprocess_pid] = { log: ffmpeg_preprocess_log }
            ffmpeg_inputs << { filename: "pipe:#{ffmpeg_preprocess_read.fileno}", format: 'nut' }
            ffmpeg_input_pipes[ffmpeg_preprocess_read] = ffmpeg_preprocess_read
            ffmpeg_filter << "[#{input_index}]"
            # Scale the video length for the deskshare timestamp workaround
            ffmpeg_filter << "setpts=PTS*#{scale}," unless scale.nil?
            # Extend the video if needed and clean up the framerate
            ffmpeg_filter << "tpad=stop=-1:stop_mode=clone,fps=#{layout[:framerate]}:start_time=#{ms_to_s(in_time)}"
            # Apply PTS offset so '0' time is aligned, and trim frames before start point
            ffmpeg_filter << ",setpts=PTS-#{ms_to_s(in_time)}/TB,trim=start=0"
            # Trim frames after stop time, which can be generated by the pre-processing ffmpeg if there's an unlucky
            # large timestamp gap before a frame which changes resolution.
            # The trim filter is needed to eat these frames so they don't queue up on the inputs of overlays.
            ffmpeg_filter << ",trim=end=#{ms_to_s(duration)}"
            ffmpeg_filter << "[#{pad_name}];"
          end

          # Create the video rows
          remaining = video_count
          (0...tiles_v).each do |tile_y|
            this_tiles_h = [tiles_h, remaining].min
            remaining -= this_tiles_h

            (0...this_tiles_h).each do |tile_x|
              ffmpeg_filter << "[#{layout_area[:name]}_x#{tile_x}_y#{tile_y}]"
            end
            if this_tiles_h > 1
              ffmpeg_filter << "hstack=inputs=#{this_tiles_h},"
            end
            ffmpeg_filter << "pad=w=#{layout_area[:width]}:h=#{tile_height}:color=#{background_color}"
            ffmpeg_filter << "[#{layout_area[:name]}_y#{tile_y}];"
          end

          # Stack the video rows
          (0...tiles_v).each do |tile_y|
            ffmpeg_filter << "[#{layout_area[:name]}_y#{tile_y}]"
          end
          if tiles_v > 1
            ffmpeg_filter << "vstack=inputs=#{tiles_v},"
          end
          ffmpeg_filter << "pad=w=#{layout_area[:width]}:h=#{layout_area[:height]}:color=#{background_color}"
          ffmpeg_filter << "[#{layout_area[:name]}];"
          ffmpeg_filter << "[#{layout_area[:name]}_in][#{layout_area[:name]}]overlay=x=#{layout_area[:x] + tiles_pad_x}:y=#{layout_area[:y] + tiles_pad_y}"
        end

        ffmpeg_filter << ",trim=end=#{ms_to_s(duration)}"

        ffmpeg_cmd = [*FFMPEG, '-copyts']
        ffmpeg_inputs.each do |input|
          ffmpeg_cmd << '-ss' << ms_to_s(input[:seek]) if input.include?(:seek)
          ffmpeg_cmd << '-f' << input[:format] if input.include?(:format)
          ffmpeg_cmd << '-i' << input[:filename]
        end

        BigBlueButton.logger.debug('  ffmpeg filter_complex_script:')
        BigBlueButton.logger.debug(ffmpeg_filter)
        filter_complex_script = "#{output}.filter"
        File.open(filter_complex_script, 'w') do |io|
          io.write(ffmpeg_filter)
        end
        ffmpeg_cmd += ['-filter_complex_script', filter_complex_script]

        ffmpeg_cmd += ['-an', *FFMPEG_WF_ARGS, '-r', layout[:framerate].to_s, output]

        BigBlueButton.logger.info("Executing: #{Shellwords.join(ffmpeg_cmd)}")
        ffmpeg_log = "#{output}.log"
        ffmpeg_pid = spawn(*ffmpeg_cmd, err: [ffmpeg_log, 'w'], **ffmpeg_input_pipes)
        # We are explicitly keeping our copy of the read side of the pipes open here, since if there
        # are any preprocessing ffmpeg commands still running when the main ffmpeg exits, we want to
        # be able to signal them to exit cleanly while they're blocked trying to write. If the pipe
        # was closed, they would exit with an error code before we can do anything.

        ffmpeg_exitok = []
        loop do
          pid, exitstatus = Process.waitpid2(-1)
          if pid == ffmpeg_pid
            BigBlueButton.logger.debug("ffmpeg command #{exitstatus} (#{File.basename(ffmpeg_log)})")

            # Tell any preprocessing ffmpeg processes which are blocking on writing
            # to the pipe to exit cleanly
            Process.kill('TERM', *aux_ffmpeg_processes.keys) unless aux_ffmpeg_processes.empty?
            # Then unblock them by closing our copy of the read side of the pipe
            ffmpeg_input_pipes.each_value(&:close)

            ffmpeg_exitok << exitstatus.success?
            log = ffmpeg_log
          else
            process = aux_ffmpeg_processes.delete(pid)
            BigBlueButton.logger.debug("preprocessing ffmpeg command #{exitstatus} (#{File.basename(process[:log])})")

            # Exit code 255 indicates that ffmpeg was terminated due to user request by signal
            ffmpeg_exitok << (exitstatus.success? || exitstatus.exitstatus == 255)
            log = process[:log]
          end

          # Read the temporary log file and include its contents into the processing log
          File.open(log, 'r') do |io|
            io.each_line do |line|
              BigBlueButton.logger.info(line.chomp!)
            end
          end
        rescue Errno::ECHILD
          # All child ffmpeg processes have exited
          break
        end

        raise 'At least one ffmpeg process failed' unless ffmpeg_exitok.all?

        BigBlueButton.logger.info('All ffmpeg processes exited normally')

        return output
      end

      # Helper method to get all packet PTS times and keyframe PTS times from a video file.
      # Returns a hash {pts_times: [float], keyframe_pts_times: [float]} or nil on error.
      def self.get_packet_and_keyframe_times(filename)
        ffprobe_cmd = [
          *FFPROBE, '-v', 'error', '-select_streams', 'v:0',
          '-show_entries', 'packet=pts_time,flags', '-of', 'json', filename
        ]
        BigBlueButton.logger.debug "Getting packet and keyframe times for '#{File.basename(filename)}': #{Shellwords.join(ffprobe_cmd)}"
        begin
          output = IO.popen(ffprobe_cmd) { |io| io.read }
          data = JSON.parse(output, symbolize_names: true)
          
          pts_times = []
          keyframe_pts_times = []

          if data[:packets] && data[:packets].is_a?(Array)
            data[:packets].each do |packet|
              next unless packet[:pts_time] # Skip packets without pts_time
              pts_time = packet[:pts_time].to_f
              pts_times << pts_time
              keyframe_pts_times << pts_time if packet[:flags]&.include?('K')
            end
          end
          
          # Ensure keyframe_pts_times are sorted and unique, as ffprobe might list them out of order or duplicate if packets are reordered.
          # pts_times from ffprobe json output for packets should already be in presentation order.
          # However, defensive sorting for keyframes is good.
          { pts_times: pts_times.sort.uniq, keyframe_pts_times: keyframe_pts_times.sort.uniq }
        rescue JSON::ParserError => e
          BigBlueButton.logger.error "Failed to parse ffprobe JSON output for packet/keyframe times from '#{File.basename(filename)}': #{e.message}"
          nil
        rescue StandardError => e
          BigBlueButton.logger.error "Error getting packet/keyframe times from '#{File.basename(filename)}': #{e.message}"
          nil
        end
      end
    end
  end
end
