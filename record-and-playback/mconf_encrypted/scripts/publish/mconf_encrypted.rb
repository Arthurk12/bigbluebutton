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

require '../../core/lib/recordandplayback'
require 'rubygems'
require 'yaml'
require 'cgi'
require 'digest/md5'
require 'digest/sha1'
require 'optimist'

bbb_props = YAML::load(File.open('../../core/scripts/bigbluebutton.yml'))

recording_dir = bbb_props['recording_dir']
playback_host = bbb_props['playback_host']
playback_protocol = bbb_props['playback_protocol']
published_dir = bbb_props['published_dir']
raw_presentation_src = bbb_props['raw_presentation_src']

opts = Optimist::options do
  opt :meeting_id, "Meeting id to publish", :default => '58f4a6b3-cd07-444d-8564-59116cb53974', :type => String
end

meeting_id = opts[:meeting_id]
match = /(.*)-(.*)/.match meeting_id
meeting_id = match[1]
playback = match[2]

begin
  if (playback == "mconf_encrypted")
    BigBlueButton.logger = Logger.new("/var/log/bigbluebutton/mconf_encrypted/publish-#{meeting_id}.log", 'daily' )

    meeting_publish_dir = "#{recording_dir}/publish/mconf_encrypted/#{meeting_id}"
    meeting_published_dir = "#{recording_dir}/published/mconf_encrypted/#{meeting_id}"
    meeting_raw_dir = "#{recording_dir}/raw/#{meeting_id}"
    meeting_raw_presentation_dir = "#{raw_presentation_src}/#{meeting_id}"

    if not FileTest.directory?(meeting_publish_dir)
      FileUtils.mkdir_p meeting_publish_dir

      Dir.chdir("#{recording_dir}/raw") do
        command = "tar -czf #{meeting_publish_dir}/#{meeting_id}.tar.gz #{meeting_id}"
        output = `#{command}`
        unless $?.success?
          raise "Couldn't compress the raw files"
        end
      end

      Dir.chdir(meeting_publish_dir) do
        metadata = BigBlueButton::Events.get_meeting_metadata("#{meeting_raw_dir}/events.xml")

        length = 16
        chars = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
        password = ''
        length.times { password << chars[rand(chars.size)] }

        passfile = File.new("#{meeting_id}.txt", "w")
        passfile.write "#{password}"
        passfile.close

        # generate encoded cleanup URL
        properties = Hash[File.read("/etc/bigbluebutton/bbb-web.properties", :encoding => "ISO-8859-1:UTF-8").scan(/(.+?)=(.+)/)]
        method = "deleteRecordings"
        params = "recordID=#{meeting_id}"
        checksum = Digest::SHA1.hexdigest "#{method}#{params}#{properties['securitySalt']}"
        delete_url = "#{properties['bigbluebutton.web.serverURL']}/bigbluebutton/api/#{method}?#{params}&checksum=#{checksum}"
        command = "echo '#{delete_url}' | openssl enc -aes-256-cbc -pass file:#{meeting_id}.txt -a -salt"
        delete_url_enc = nil
        output = `#{command}`
        if $?.success?
          delete_url_enc = output.strip
        else
          BigBlueButton.logger.warn "Couldn't add the deleteRecordings URL, leave it"
        end

        # encrypt files
        command = "openssl enc -aes-256-cbc -pass file:#{meeting_id}.txt < #{meeting_id}.tar.gz > #{meeting_id}.dat"
        output = `#{command}`
        unless $?.success?
          raise "Couldn't encrypt the recording file using the random key"
        end

        FileUtils.rm_f "#{meeting_id}.tar.gz"

        key_filename = ""
        if metadata.has_key?('mconflb-rec-server-key') and not metadata['mconflb-rec-server-key'].to_s.empty?
          key_filename = "#{meeting_id}.enc"
          # the key is already unescaped in the metadata
          public_key_decoded = "#{metadata['mconflb-rec-server-key'].to_s}"
          public_key_filename = "public-key.pem"
          public_key = File.new("#{public_key_filename}", "w")
          public_key.write "#{public_key_decoded}"
          public_key.close

          command = "openssl rsautl -encrypt -pubin -inkey #{public_key_filename} < #{meeting_id}.txt > #{meeting_id}.enc"
          output = `#{command}`
          unless $?.success?
            raise "Couldn't encrypt the random key using the server public key passed as metadata"
          end

          FileUtils.rm_f ["#{meeting_id}.txt", "#{public_key_filename}"]
        else
          key_filename = "#{meeting_id}.txt"
          BigBlueButton.logger.warn "No public key was found in the meeting's metadata"
        end

        # generate md5 checksum
        md5sum = Digest::MD5.file("#{meeting_id}.dat")

        BigBlueButton.logger.info("Creating metadata.xml")

        events = Nokogiri::XML(File.open("#{meeting_raw_dir}/events.xml")) { |x| x.noblanks }

        # Get the real-time start and end timestamp
        meeting_start = BigBlueButton::Events.first_event_timestamp(events)
        meeting_end = BigBlueButton::Events.last_event_timestamp(events)
        match = /.*-(\d+)$/.match(meeting_id)
        real_start_time = match[1]
        real_end_time = (real_start_time.to_i + (meeting_end.to_i - meeting_start.to_i)).to_s

        metadata["mconf-decrypter-pending"] = true
        if not delete_url_enc.nil?
          metadata["mconf-decrypter-cleanup-url"] = delete_url_enc
        end

        # Create metadata.xml
        b = Builder::XmlMarkup.new(:indent => 2)
        metaxml = b.recording {
          b.id(meeting_id)
          b.state("published")
          b.published(true)
          # Date Format for recordings: Thu Mar 04 14:05:56 UTC 2010
          b.start_time(real_start_time)
          b.end_time(real_end_time)
          b.participants(BigBlueButton::Events.get_num_participants(events))
          b.download {
            b.format("encrypted")
            b.link("#{playback_protocol}://#{playback_host}/mconf_encrypted/#{meeting_id}/#{meeting_id}.dat")
            b.md5(md5sum)
            b.key("#{playback_protocol}://#{playback_host}/mconf_encrypted/#{meeting_id}/#{key_filename}")
          }
          b.meta {
            metadata.each { |k,v| b.method_missing(k,v) }
          }
        }

        recording = Nokogiri::XML(metaxml).root

        ## Copy the breakout and breakout rooms node from
        ## events.xml if present.
        breakout_xpath = events.xpath("/recording/breakout")
        breakout_rooms_xpath = events.xpath("/recording/breakoutRooms")
        meeting_xpath = events.xpath("/recording/meeting")

        if (meeting_xpath != nil)
          recording << meeting_xpath
        end

        if (breakout_xpath != nil)
          recording << breakout_xpath
        end

        if (breakout_rooms_xpath != nil)
          recording << breakout_rooms_xpath
        end

        metadata_xml = File.new("metadata.xml","w")
        metadata_xml.write(recording.to_xml(:indent => 2))
        metadata_xml.close

        # After all the processing we'll add the published format and raw sizes to the metadata file
        BigBlueButton.add_raw_size_to_metadata(meeting_publish_dir, meeting_raw_dir)
        BigBlueButton.add_download_size_to_metadata(meeting_publish_dir)

        BigBlueButton.logger.info("Publishing mconf_encrypted")

        # Now publish this recording
        if not FileTest.directory?("#{published_dir}/mconf_encrypted")
          FileUtils.mkdir_p "#{published_dir}/mconf_encrypted"
        end
        BigBlueButton.logger.info("Publishing files")
        FileUtils.mv(meeting_publish_dir, "#{published_dir}/mconf_encrypted")

        BigBlueButton.logger.info("Removing the recording raw files: #{meeting_raw_dir}")
        FileUtils.rm_r meeting_raw_dir, :force => true
        BigBlueButton.logger.info("Removing the recording presentation: #{meeting_raw_presentation_dir}")
        FileUtils.rm_r meeting_raw_presentation_dir, :force => true

        publish_done = File.new("#{recording_dir}/status/published/#{meeting_id}-mconf_encrypted.done", "w")
        publish_done.write("Published #{meeting_id}")
        publish_done.close
      end
    end
  end
rescue Exception => e
  BigBlueButton.logger.error(e.message)
  e.backtrace.each do |traceline|
    BigBlueButton.logger.error(traceline)
  end
  publish_done = File.new("#{recording_dir}/status/published/#{meeting_id}-mconf_encrypted.fail", "w")
  publish_done.write("Failed Publishing #{meeting_id}")
  publish_done.close

  exit 1
end
