#!/usr/bin/ruby
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
require 'net/http'
require 'net/https'
require 'rexml/document'
require 'open-uri'
require 'digest/md5'

BigBlueButton.logger = Logger.new("/var/log/bigbluebutton/mconf_decrypter.log",'daily' )
#BigBlueButton.logger = Logger.new(STDOUT)

bbb_props = YAML::load(File.open('../../core/scripts/bigbluebutton.yml'))
mconf_props = YAML::load(File.open('mconf-decrypter.yml'))

# these properties must be global variables (starting with $)
$private_key = mconf_props['private_key']
$get_recordings_url = mconf_props['get_recordings_url']
$verify_ssl_certificate = mconf_props['verify_ssl_certificate']
$recording_dir = bbb_props['recording_dir']
$raw_dir = "#{$recording_dir}/raw"
$archived_dir = "#{$recording_dir}/status/archived"

def getRequest(url)
  BigBlueButton.logger.debug("Fetching #{url}")
  url_parsed = URI.parse(url)
  http = Net::HTTP.new(url_parsed.host, url_parsed.port)
  http.use_ssl = (url_parsed.scheme.downcase == "https")
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE if http.use_ssl? && ! $verify_ssl_certificate
  http.get(url_parsed.request_uri)
end

def fetchRecordings(url)
  doc = nil
  begin
    response = getRequest(url)
    # follow redirects once only
    if response.kind_of?(Net::HTTPRedirection)
      BigBlueButton.logger.debug("Received a redirect, will make a new request")
      response = getRequest(response['location'])
    end

    doc = Nokogiri::XML(response.body)
    returncode = doc.xpath("//returncode")
    if returncode.empty? or returncode.text != "SUCCESS"
      BigBlueButton.logger.error "getRecordings didn't return success:\n#{doc.to_xml(:indent => 2)}"
      return false
    end
  rescue
    BigBlueButton.logger.error("Exception occurred: #{$!}")
    return false
  end

  doc.xpath("//recording").each do |recording|
    record_id = recording.xpath(".//recordID").text
    recording.xpath(".//download/format").each do |format|
      type = format.xpath(".//type").text
      if type == "encrypted"
        meeting_id = record_id
        file_url = format.xpath(".//url").text
        key_file_url = format.xpath(".//key").text
        md5_value = format.xpath(".//md5").text

        encrypted_file = file_url.split("/").last
        decrypted_file = File.basename(encrypted_file, '.*') + ".tar.gz"
        # can't check only for archived.done because when the file is published, the archived flag is removed
        # so we check for any .done file
        # we use **/*/** so it will work if a status directory is replaced by a symbolic link
        if Dir.glob(["#{$recording_dir}/status/**/*/**/#{record_id}*.done", "#{$recording_dir}/raw/#{record_id}"]).empty?
          Dir.chdir($raw_dir) do
            BigBlueButton.logger.info("Next recording to be processed is #{meeting_id}")

            BigBlueButton.logger.debug("Removing any file previously downloaded related to this recording")
            FileUtils.rm_r Dir.glob("#{$raw_dir}/#{record_id}*"), :force => true

            BigBlueButton.logger.debug("recordID = #{record_id}")
            BigBlueButton.logger.debug("file_url = #{file_url}")
            BigBlueButton.logger.debug("key_file_url = #{key_file_url}")
            BigBlueButton.logger.debug("md5_value = #{md5_value}")

            BigBlueButton.logger.info("Checking if #{file_url} exists")
            command = "curl --silent --max-time 10 --output /dev/null --fail --head \"#{file_url}\""
            BigBlueButton.logger.debug("Running: #{command}")
            output = `#{command}`
            unless $?.success?
              BigBlueButton.logger.error "Couldn't reach raw files"
              next
            end

            BigBlueButton.logger.info("Downloading the encrypted file to #{encrypted_file}")

            `timeout -s KILL 7200 wget --no-verbose --output-document "#{encrypted_file}" "#{file_url}"`
            wget_return = $?

            md5_calculated = Digest::MD5.file(encrypted_file)

            if md5_calculated == md5_value
              BigBlueButton.logger.info("The calculated MD5 matches the expected value")
              key_file = key_file_url.split("/").last
              decrypted_key_file = File.basename(key_file, '.*') + ".txt"

              BigBlueButton.logger.info("Downloading the key file to #{key_file}")
              writeOut = open(key_file, "wb")
              writeOut.write(open(key_file_url).read)
              writeOut.close

              if key_file != decrypted_key_file
                BigBlueButton.logger.debug("Locating private key")
                if not File.exists?("#{$private_key}")
                  BigBlueButton.logger.error "Couldn't find the private key on #{$private_key}"
                  next
                end
                BigBlueButton.logger.debug("Decrypting recording key")
                command = "openssl rsautl -decrypt -inkey #{$private_key} < #{key_file} > #{decrypted_key_file}"
                BigBlueButton.logger.debug("Running: #{command}")
                output = `#{command}`
                unless $?.success?
                  BigBlueButton.logger.error "Couldn't decrypt the random key with the server private key"
                  next
                end
                FileUtils.rm_r "#{key_file}"
              else
                BigBlueButton.logger.info("No public key was used to encrypt the random key")
              end

              BigBlueButton.logger.debug("Decrypting the recording file")
              command = "openssl enc -aes-256-cbc -d -pass file:#{decrypted_key_file} < #{encrypted_file} > #{decrypted_file}"
              BigBlueButton.logger.debug("Running: #{command}")
              output = `#{command}`
              is_valid = false

              if $?.success?
                command = "gzip -t #{decrypted_file}"
                BigBlueButton.logger.debug("Running: #{command}")
                output = `#{command}`
                is_valid = $?.success?
              end

              unless is_valid
                # this step is needed because openssl 1.1.0 uses sha256 by default, see: https://www.openssl.org/docs/faq.html#USER3
                command = "openssl enc -aes-256-cbc -d -md sha256 -pass file:#{decrypted_key_file} < #{encrypted_file} > #{decrypted_file}"
                BigBlueButton.logger.debug("Running: #{command}")
                output = `#{command}`
                unless $?.success?
                  BigBlueButton.logger.error "Couldn't decrypt the recording file using the random key"
                  next
                end
              end

              command = "tar -zxf #{decrypted_file}"
              BigBlueButton.logger.debug("Running: #{command}")
              output = `#{command}`
              unless $?.success?
                BigBlueButton.logger.error "Couldn't extract the raw files"
                next
              end

              node = recording.at_xpath(".//metadata/mconf-decrypter-cleanup-url")
              unless node.nil?
                delete_url = nil
                encoded_url = node.text
                command  = "echo '#{encoded_url}' | openssl enc -aes-256-cbc -d -pass file:#{decrypted_key_file} -a -salt"
                BigBlueButton.logger.debug("Running: #{command}")
                output = `#{command}`
                if $?.success?
                  delete_url = output.strip
                end
                if not $?.success? or not delete_url.start_with?("http")
                  delete_url = nil
                  # this step is needed because openssl 1.1.0 uses sha256 by default, see: https://www.openssl.org/docs/faq.html#USER3
                  command  = "echo '#{encoded_url}' | openssl enc -aes-256-cbc -d -md sha256 -pass file:#{decrypted_key_file} -a -salt"
                  BigBlueButton.logger.debug("Running: #{command}")
                  output = `#{command}`
                  if $?.success?
                    delete_url = output.strip
                  end
                end

                unless delete_url.nil?
                  command = "curl -s '#{delete_url}'"
                  BigBlueButton.logger.debug("Running: #{command}")
                  output = `#{command}`
                  if $?.success?
                    BigBlueButton.logger.info "Encrypted format deleted successfully"
                  else
                    BigBlueButton.logger.warn "Couldn't delete encrypted format"
                  end
                else
                  BigBlueButton.logger.warn "Couldn't add the deleteRecordings URL, leave it"
                end
              end

              xml_filename = "#{$raw_dir}/#{record_id}/events.xml"
              doc = Nokogiri::XML(File.open(xml_filename)) { |x| x.noblanks }
              [ "/recording/metadata/mconflb-rec-server-key",
                "/recording/metadata/mconflb-rec-server-url",
                "/recording/metadata/mconf-decrypter-cleanup-url" ].each do |query|
                  doc.xpath(query).each do |node|
                      node.remove if ! node.nil?
                  end
              end

              node = doc.at_xpath("/recording/metadata/mconf-decrypter-pending")
              node.content = "false" unless node.nil?

              xml_file = File.new(xml_filename, "w")
              xml_file.write(doc.to_xml(:indent => 2))
              xml_file.close

              archived_done = File.new("#{$archived_dir}/#{meeting_id}.done", "w")
              archived_done.write("Archived #{meeting_id}")
              archived_done.close

              [ "#{encrypted_file}", "#{decrypted_file}", "#{decrypted_key_file}" ].each { |file|
                BigBlueButton.logger.info("Removing #{file}")
                FileUtils.rm_r "#{file}"
              }

              BigBlueButton.logger.info("Recording #{record_id} decrypted successfully")

            else
              if wget_return == "8"
                BigBlueButton.logger.warn("Raw files for #{record_id} no longer exist")
              else
                BigBlueButton.logger.error("The calculated MD5 doesn't match the expected value")
              end
              FileUtils.rm_f(encrypted_file)
            end
          end
        end
      end
    end
  end
  return true
end

def processGetRecordingsUrlInput(input)
  if input.respond_to? "each"
    input.each do |url|
      processGetRecordingsUrlInput url
    end
  else
    fetchRecordings input
  end
end

processGetRecordingsUrlInput $get_recordings_url if !$get_recordings_url.nil? and !$get_recordings_url.empty?
