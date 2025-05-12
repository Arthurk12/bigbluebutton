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

require_relative 'boot'

require 'recordandplayback/events_archiver'
require 'recordandplayback/generators/events'
require 'recordandplayback/generators/audio'
require 'recordandplayback/generators/video'
require 'recordandplayback/generators/audio_processor'
require 'recordandplayback/generators/presentation'
require 'custom_hash'
require 'etherpad'
require 'open4'
require 'pp'
require 'absolute_time'
require 'logger'
require 'find'
require 'rubygems'
require 'timeout'
require 'uri'
require 'net/http'
require 'shellwords'
require 'English'

module BigBlueButton
  class MissingDirectoryException < RuntimeError
  end

  class FileNotFoundException < RuntimeError
  end

  class AsyncProcess
    attr_accessor :command
    attr_accessor :pid
    attr_accessor :stdin
    attr_accessor :stdout
    attr_accessor :stderr
  end

  class ExecutionStatus
    def initialize
      @output = []
      @errors = []
      @detailedStatus = nil
    end

    attr_accessor :output
    attr_accessor :errors
    attr_accessor :detailedStatus

    def success?
      @detailedStatus.success?
    end

    def exited?
      @detailedStatus.exited?
    end

    def exitstatus
      @detailedStatus.exitstatus
    end
  end

  # BigBlueButton logs information about its progress.
  # Replace with your own logger if you desire.
  #
  # @param [Logger] log your own logger
  # @return [Logger] the logger you set
  def self.logger=(log)
    @logger = log
  end

  # Get BigBlueButton logger.
  #
  # @return [Logger]
  def self.logger
    return @logger if @logger
    logger = Logger.new(STDOUT)
    logger.level = Logger::INFO
    @logger = logger
  end

  def self.redis_publisher=(publisher)
    @redis_publisher = publisher
  end

  def self.redis_publisher
    return @redis_publisher
  end

  def self.execute_async(command)
    BigBlueButton.logger.info("Executing async: #{command}")
    proc = AsyncProcess.new
    proc.command = command
    proc.pid, proc.stdin, proc.stdout, proc.stderr = Open4::popen4 proc.command
    BigBlueButton.logger.info("Process just created with PID #{proc.pid}")
    proc
  end

  # http://stackoverflow.com/a/3568291/1006288
  def self.is_running?(proc)
    begin
      Process.getpgid( proc.pid )
      true
    rescue Errno::ESRCH
      false
    end
  end

  def self.kill(proc, signal = "TERM")
    BigBlueButton.logger.info("Killing PID #{proc.pid} with signal #{signal}: #{proc.command}")

    if not is_running?(proc)
      BigBlueButton.logger.info "Trying to kill a process that isn't running, skipping"
      return
    end

    proc.stdin.close unless proc.stdin.closed?

    begin
      Process.kill signal, proc.pid
    rescue Exception => e
      if e.message == "No such process"
        BigBlueButton.logger.info "Trying to kill a process that doesn't exist anymore, skipping"
      else
        BigBlueButton.logger.error "Something went wrong while killing PID #{proc.pid}: #{e.to_s}"
        raise e
      end
    end
  end

  def self.wait(proc, timeout_sec=30, fail_on_error=true)
    BigBlueButton.logger.info("Waiting PID #{proc.pid} to die (max. #{timeout_sec} seconds): #{proc.command}")

    if not is_running?(proc)
      BigBlueButton.logger.info "Trying to wait a process that isn't running, skipping"
      return
    end

    begin
      Timeout::timeout(timeout_sec) {
        pid_returned, status = Process.waitpid2 proc.pid

        BigBlueButton.logger.info("Process status: #{status.to_s}")
        BigBlueButton.logger.info("Process exited? #{status.exited?}")

        out = proc.stdout.readlines
        BigBlueButton.logger.info( "stdout:\n #{Array(out).join()} ") unless out.empty?

        err = proc.stderr.readlines
        BigBlueButton.logger.error( "stderr:\n #{Array(err).join()} ") unless err.empty?

        if status.exited?
          BigBlueButton.logger.info("Success?: #{status.success?}")
          BigBlueButton.logger.info("Exit status: #{status.exitstatus}")
          if status.success? == false and fail_on_error
            raise "Execution failed"
          end
        end
      }
    rescue Timeout::Error
      BigBlueButton.logger.info("PID #{proc.pid} didn't ended in #{timeout_sec} seconds")
      if is_running?(proc)
        BigBlueButton.logger.error "PID #{proc.pid} is still running, raising an exception"
        raise
      else
        BigBlueButton.logger.info "PID #{proc.pid} is not running anymore, skipping"
      end
    rescue Exception => e
      if e.message == "No child processes"
        BigBlueButton.logger.info "Trying to wait a process that doesn't exist anymore, skipping"
      else
        BigBlueButton.logger.error "Something went wrong while waiting for PID #{proc.pid}: #{e.to_s}"
        raise e
      end
    end
    BigBlueButton.logger.debug "Returning from wait"
  end

  def self.execute(command, fail_on_error = true)
    BigBlueButton.logger.info("Executing: #{command.respond_to?(:to_ary) ? Shellwords.join(command) : command}")
    IO.popen(command, err: %i[child out]) do |io|
      io.each_line do |line|
        BigBlueButton.logger.info(line.chomp)
      end
    end
    status = $CHILD_STATUS

    BigBlueButton.logger.info("Success?: #{status.success?}")
    BigBlueButton.logger.info("Process exited? #{status.exited?}")
    BigBlueButton.logger.info("Exit status: #{status.exitstatus}")
    raise 'Execution failed' if status.success? == false && fail_on_error

    status
  end

  def self.exec_ret(*command)
    execute(command, false).exitstatus
  end

  def self.exec_redirect_ret(outio, *command)
    BigBlueButton.logger.info "Executing: #{Shellwords.join(command)}"
    BigBlueButton.logger.info "Sending output to #{outio}"
    IO.pipe do |r, w|
      pid = spawn(*command, :out => outio, :err => w)
      w.close
      r.each_line do |line|
        BigBlueButton.logger.info line.chomp
      end
      Process.waitpid(pid)
      BigBlueButton.logger.info "Exit status: #{$?.exitstatus}"
      return $?.exitstatus
    end
  end

  def self.hash_to_str(hash)
    return PP.pp(hash, "")
  end

  def self.isset(name)
    ENV[name] && ENV[name] != '0' && ENV[name].strip != ''
  end

  def self.monotonic_clock()
    return (AbsoluteTime.now * 1000).to_i
  end

  def self.download(url, output)
    BigBlueButton.logger.info "Downloading #{url} to #{output}"

    uri = URI.parse(url)
    if ["http", "https", "ftp"].include? uri.scheme
      response = Net::HTTP.start(uri.host, uri.port) {|http|
        http.head(uri.request_uri)
      }
      unless response.is_a? Net::HTTPSuccess
        raise "File not available: #{response.message}"
      end
    end

    if uri.scheme.nil?
      url = "file://" + url
      uri = URI.parse(url)
    end

    if defined? uri.request_uri
      Net::HTTP.start(uri.host, uri.port) do |http|
        request = Net::HTTP::Get.new uri.request_uri
        http.request request do |response|
          open output, 'w' do |io|
            response.read_body do |chunk|
              io.write chunk
            end
          end
        end
      end
    else
      command = "curl --location --output #{output} #{url}"
      BigBlueButton.execute(command)
    end
  end

  def self.try_download(url, output)
    begin
      self.download(url, output)
    rescue Exception => e
      BigBlueButton.logger.error "Failed to download file: #{e.to_s}"
      FileUtils.rm_f output
    end
  end

  def self.get_dir_size(dir_name)
    size = 0
    if FileTest.directory?(dir_name)
      Find.find(dir_name) {|f| size += File.size(f)}
    end
    size.to_s
  end

  def self.add_tag_to_xml(xml_filename, parent_xpath, tag, content)
    if File.exist? xml_filename
      doc = Nokogiri::XML(File.read(xml_filename)) {|x| x.noblanks}

      doc.xpath("#{parent_xpath}/#{tag}").each do |node|
        node.remove
      end

      node = Nokogiri::XML::Node.new tag, doc
      node.content = content

      doc.at(parent_xpath) << node

      xml_file = File.new(xml_filename, "w")
      xml_file.write(doc.to_xml(:indent => 2))
      xml_file.close
    end
  end

  def self.add_raw_size_to_metadata(dir_name, raw_dir_name)
    size = BigBlueButton.get_dir_size(raw_dir_name)
    BigBlueButton.add_tag_to_xml("#{dir_name}/metadata.xml", "//recording", "raw_size", size)
  end

  def self.add_playback_size_to_metadata(dir_name)
    size = BigBlueButton.get_dir_size(dir_name)
    BigBlueButton.add_tag_to_xml("#{dir_name}/metadata.xml", "//recording/playback", "size", size)
  end

  def self.add_download_size_to_metadata(dir_name)
    size = BigBlueButton.get_dir_size(dir_name)
    BigBlueButton.add_tag_to_xml("#{dir_name}/metadata.xml", "//recording/download", "size", size)
  end

  def self.record_id_to_timestamp(r)
    r.split("-")[1].to_i / 1000
  end

  def self.get_metadata_from_recording(recording)
    metadata = {}
    if ! recording[:meta].nil?
      metadata = recording[:meta]
      # Guarantee a string value at meetingName
      metadata[:meetingName] = metadata[:meetingName].to_s if ! metadata[:meetingName].nil?
    end
    metadata
  end

  def self.done_to_timestamp(r)
    BigBlueButton.record_id_to_timestamp(File.basename(r, ".done"))
  end

  def self.rap_core_path
    File.expand_path('../../', __FILE__)
  end

  def self.rap_scripts_path
    File.join(BigBlueButton.rap_core_path, 'scripts')
  end

  def self.read_props
    return @props if @props

    filepathRecOverride = "/etc/bigbluebutton/recording/recording.yml"
    hasOverride = File.file?(filepathRecOverride)
    
    filepath = File.join(BigBlueButton.rap_scripts_path, 'bigbluebutton.yml')
    @props = YAML::load(File.open(filepath))
    if (hasOverride)
      recOverrideProps = YAML::load(File.open(filepathRecOverride))
      @props = @props.merge(recOverrideProps)
    end
    @props
  end

  def self.create_redis_publisher
    props = BigBlueButton.read_props
    redis_host = props['redis_host']
    redis_port = props['redis_port']
    redis_password = props['redis_password']
    BigBlueButton.redis_publisher = BigBlueButton::RedisWrapper.new(redis_host, redis_port, redis_password)
  end

  def self.find_intersection(periods1, periods2)
    intersections = []

    periods1.each do |start1, stop1|
      periods2.each do |start2, stop2|
        # Find the overlapping interval
        overlap_start = [start1, start2].max
        overlap_stop = [stop1, stop2].min

        # If there is an overlap, add it to the intersections array
        if overlap_start <= overlap_stop
          intersections << [overlap_start, overlap_stop]
        end
      end
    end

    intersections
  end

  def self.merge_periods(periods)
    return [] if periods.empty?

    # Sort periods by start time
    sorted_periods = periods.sort_by { |start, _| start }
    merged = [sorted_periods[0]]

    sorted_periods[1..-1].each do |current_start, current_stop|
      last_start, last_stop = merged.last
      if current_start <= last_stop
        # Overlapping periods, merge them
        merged[-1] = [last_start, [last_stop, current_stop].max]
      else
        # Non-overlapping, add to merged
        merged << [current_start, current_stop]
      end
    end

    merged
  end

  def self.subtract_periods(periods1, periods2)
    # Merge both sets of periods to handle overlaps
    merged_periods1 = self.merge_periods(periods1)
    merged_periods2 = self.merge_periods(periods2)

    result = []
    merged_periods1.each do |start1, stop1|
      # Start with the full period from periods1
      current_start = start1
      current_stop = stop1

      merged_periods2.each do |start2, stop2|
        # Skip if the period from periods2 is completely before or after the current period
        next if stop2 < current_start || start2 > current_stop

        # If the period from periods2 overlaps with the current period, split it
        if start2 > current_start
          # Add the non-overlapping part before the overlapping period
          result << [current_start, start2]
        end

        # Update the current period to the remaining part after the overlapping period
        current_start = [current_start, stop2].max

        # If the current period is completely consumed, break
        break if current_start >= current_stop
      end

      # Add the remaining part of the current period if it's not fully consumed
      if current_start < current_stop
        result << [current_start, current_stop]
      end
    end

    result
  end
end
