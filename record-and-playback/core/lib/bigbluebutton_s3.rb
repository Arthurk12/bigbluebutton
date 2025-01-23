# Set encoding to utf-8
# encoding: UTF-8

require 'aws-sdk-s3'
require 'date'
require 'dotenv'
require 'json'
require 'logger'
require 'mime-types'
require 'nokogiri'
require 'pathname'
require 'retriable'
require 'stringio'
require 'uri'

require File.expand_path(File.join(File.dirname(__FILE__), 'custom_hash'))

module BigBlueButtonS3
  MAX_ATTEMPTS = 20
  MAX_ELAPSED_TIME = 1800

  # match for:
  # presentation_video/meeting_id/teste.mp4
  # presentation_video/meeting_id/teste.webm
  # video/meeting_id/teste.mp4
  # video/meeting_id/teste.webm
  # the only group is :extension, the other groups are ignored
  DOWNLOAD_PREFIXES = [
    /^(?:presentation_)?video\/.*\/(?<filename>.*(?:mp4|webm))$/
  ]

  def self.print_retry
    return @print_retry if @print_retry
    @print_retry = Proc.new do |exception, try, elapsed_time, next_interval|
      msg = "Attempt #{try} failed due to #{exception.class}: '#{exception.message}'"
      msg += " - trying again in #{next_interval.round(1)} seconds" unless next_interval.nil?
      BigBlueButtonS3.logger.warn msg
    end
  end

  # Logs information about its progress.
  # Replace with your own logger if you desire.
  #
  # @param [Logger] log your own logger
  # @return [Logger] the logger you set
  def self.logger=(log)
    @logger = log

    Aws.config.update(
      logger: @logger
    )
  end

  # Get logger.
  #
  # @return [Logger]
  def self.logger
    return @logger if @logger
    logger = Logger.new(STDOUT)
    logger.level = Logger::INFO
    @logger = logger
  end

  class Publisher
    attr_accessor :keep_local

    def initialize(key: "", secret: "", region: nil, endpoint: nil, force_path_style: true, client: nil)
      if client.nil?
        opts = {
          :region => region
        }
        unless key.empty? or secret.empty?
          opts[:credentials] = Aws::Credentials.new(key, secret)
        end
        unless endpoint.nil? or endpoint.empty?
          opts[:endpoint] = endpoint
          opts[:force_path_style] = force_path_style
        end
        @client = Aws::S3::Client.new(opts)
      else
        @client = client
      end

      @s3 = Aws::S3::Resource.new(
        client: @client
      )

      @keep_local = isset('BBB_AWS_KEEP_LOCAL')
    end

    def publish(record_id, dir, bucket_name, formats = nil)
      publish_helper(record_id, dir, bucket_name, true, formats)
    end

    def unpublish(record_id, dir, bucket_name, formats = nil)
      publish_helper(record_id, dir, bucket_name, false, formats)
    end

    def delete(record_id, published_dir, bucket_name, formats)
      BigBlueButtonS3.logger.info "Deleting recording #{record_id}"
      prefixes = get_prefixes(record_id, published_dir, formats)
      success = true
      keys = []
      prefixes.each do |prefix|
        BigBlueButtonS3.logger.info "Processing prefix #{prefix}"
        @s3.bucket(bucket_name).objects(prefix: prefix).each do |obj|
          BigBlueButtonS3.logger.info "Deleting #{obj.key}"
          keys << {
            key: obj.key
          }
        end

        if keys.empty?
          BigBlueButtonS3.logger.info "No files to delete for #{record_id} at #{published_dir}"
          return true
        end

        output = @s3.bucket(bucket_name).delete_objects(
          {
            delete: {
              objects: keys
            }
          }
        )
        local_success = output.deleted.length == keys.length && output.errors.length == 0
        if local_success
          BigBlueButtonS3.logger.info "Successfully deleted #{keys.length} objects"
        else
          BigBlueButtonS3.logger.error "Failed to delete #{output.errors.length} of #{keys.length}"
        end
        success &= local_success
      end

      BigBlueButtonS3.logger.info "Recording #{record_id} deleted successfully" if success
      success
    end

    def upload_dir(target_dir, remote_prefix, bucket_name, metadata: {})
      compare_and_push(remote_prefix, target_dir, target_dir, bucket_name, false, metadata: metadata)
    end

    def upload_raw(record_id, bucket_name, combine: true, duration:)
      success = true

      metadata = {}
      metadata["record_id"] = record_id
      metadata["meeting_duration"] = duration.to_s unless duration.nil?

      if combine
        remote_prefix = "raw/#{record_id}.tar"
        Dir.chdir("/var/bigbluebutton/recording/raw") do
          local_dir = File.expand_path("#{record_id}.tar")
          `tar -cf "#{local_dir}" "#{record_id}"`
          success = $?.exitstatus == 0
          raise "Couldn't combine raw files" unless success

          parent_dir = File.dirname(local_dir)
          success = compare_and_push(remote_prefix, local_dir, parent_dir, bucket_name, false, metadata: metadata)
          FileUtils.rm local_dir
        end
      else
        remote_prefix = "raw/#{record_id}"
        local_dir = "/var/bigbluebutton/recording/raw/#{record_id}"
        parent_dir = local_dir
        success = compare_and_push(remote_prefix, local_dir, parent_dir, bucket_name, false)
      end
      success
    end

    def list_objects(prefix, bucket_name)
      opt = {
        bucket: bucket_name,
        max_keys: 1000,
        prefix: prefix
      }
      prefix_list = []
      loop do
        resp = @client.list_objects_v2(opt)
        opt[:continuation_token] = resp.next_continuation_token
        prefix_list += resp.contents.map{ |obj| obj.key }
        break if opt[:continuation_token].nil?
      end
      prefix_list
    end

    def download_key(key, bucket_name, parent_dir, remote_prefix)
      success = true
      target = File.join(parent_dir, path_relative_to(key, remote_prefix))
      if ! File.exists? target
        FileUtils.mkdir_p File.dirname(target)

        BigBlueButtonS3.logger.info "Downloading #{key}"

        local_success = true
        Retriable.retriable(tries: MAX_ATTEMPTS, on_retry: BigBlueButtonS3.print_retry, max_elapsed_time: MAX_ELAPSED_TIME) do
          local_success = @client.get_object({ bucket: bucket_name, key: key }, target: target)
          raise "get_object returned #{local_success}" unless local_success
        end
        success &= local_success
      end

      if File.extname(target) == ".tar"
        Dir.chdir(parent_dir) do
          `tar xf "#{target}"`
          success &= $?.exitstatus == 0
          raise "Couldn't extract raw files" unless success
          FileUtils.rm target
        end
      end

      success
    end

    def download_dir(remote_prefix, bucket_name, parent_dir)
      success = true
      prefix_list = list_objects(remote_prefix, bucket_name)
      prefix_list.each_with_index do |key, index|
        BigBlueButtonS3.logger.info "Fetching #{index+1}/#{prefix_list.length} #{key}"
        success &= download_key(key, bucket_name, parent_dir, remote_prefix)
      end

      success
    end

    def tag_dir(remote_prefix, bucket_name, tags)
      success = true
      prefix_list = list_objects(remote_prefix, bucket_name)
      prefix_list.each_with_index do |key, index|
        BigBlueButtonS3.logger.info "Tagging #{index+1}/#{prefix_list.length} #{key} with #{tags.to_json}"
        success &= tag_key(key, bucket_name, tags)
      end

      success
    end

    def tag_key(key, bucket_name, tags)
      resp = @client.put_object_tagging({
        bucket: bucket_name,
        key: key,
        tagging: {
          tag_set: tags.map{ |k, v| { key: k, value: v } }
        }
      })

      true
    end

    def download_raw(record_id, bucket_name, parent_dir)
      download_dir("raw/#{record_id}", bucket_name, parent_dir)
    end

    def tag_raw(record_id, bucket_name)
      tag_dir("raw/#{record_id}", bucket_name, { "processed" => "true" })
    end

    def upload_playbacks(playback_dir, bucket_name)
      success = true
      playbacks = Dir.glob("#{playback_dir}/*").select { |d| File.directory?(d) }
      playbacks.each do |playback_dir|
        prefix_parent = File.expand_path("#{playback_dir}/../..")
        prefix = path_relative_to(playback_dir, prefix_parent)
        BigBlueButtonS3.logger.info "Updating playback format #{prefix}"
        success &= compare_and_push(prefix, playback_dir, prefix_parent, bucket_name, true)
      end
      BigBlueButtonS3.logger.info "Playbacks updated successfully" if success
      success
    end

    def get_playback_url
      $playback_url
    end

    def get_modified_link(link)
      parsed = URI.parse(link.strip)
      url  = get_playback_url
      url += parsed.path
      url += '?' + parsed.query if parsed.query
      url += '#' + parsed.fragment if parsed.fragment
      url
    end

    def get_playback_link(metadata_file)
      doc = nil
      begin
        doc = Nokogiri::XML(open(metadata_file).read) { |x| x.noblanks }
      rescue Exception => e
        BigBlueButtonS3.logger.error "Error parsing metadata file, skipping. #{e.inspect}"
        return
      end

      doc.at("/recording/playback/link").content
    end

    def get_metadata_path(record_id, published_dir, format)
      prefixes = get_prefixes(record_id, published_dir, [format])
      "#{published_dir}/#{prefixes[0]}/metadata.xml"
    end

    def build_publish_ended_message(record_id, format, metadata_path)
      doc = Hash.from_xml(File.open(metadata_path))
      playback = doc.dig(:recording, :playback) || {}

      xml_doc = Nokogiri::XML(File.open(metadata_path)) { |x| x.noblanks }
      playback[:extensions][:preview][:images][:image] = [ playback[:extensions][:preview][:images][:image] ] if xml_doc.xpath("/recording/playback/extensions/preview/images/image").size == 1

      payload = {
        "success" => true,
        "step_time" => 0,
        "playback" => playback,
        "metadata" => doc.dig(:recording, :meta) || {},
        "download" => doc.dig(:recording, :download) || {},
        "raw_size" => doc.dig(:recording, :raw_size) || {},
        "start_time" => doc.dig(:recording, :start_time) || {},
        "end_time" => doc.dig(:recording, :end_time) || {}
      }
      payload["workflow"] = format
      external_meeting_id = doc.dig(:recording, :meta, :meetingId)
      payload["external_meeting_id"] = external_meeting_id if ! external_meeting_id.nil?
      payload["record_id"] = record_id
      payload["meeting_id"] = record_id

      header = {
        "timestamp" => (AbsoluteTime.now * 1000).to_i,
        "name" => "publish_ended",
        "current_time" => Time.now.to_i, # unix timestamp
        "version" => "0.0.1"
      }

      message = {
        "header" => header,
        "payload" => payload
      }

      message
    end

    def get_list_of_recordings(dir)
      list = Dir.glob("#{dir}/*/*")

      # reject directories not in the format we expect
      list = list.reject{ |path| /\w+-\d+/.match(File.basename(path)).nil? }

      # sort so older recordings are in the beginning
      list = list.sort{ |a,b| path_to_timestamp(a) <=> path_to_timestamp(b) }

      # map to an array in the format {"c164f71bef6ea47bd91519b54c134efb4da0d935-1480953600847"=>"presentation"}
      list = list.collect{ |path| { File.basename(path) => File.basename(File.dirname(path)) } }

      # map to an array in the format {"c164f71bef6ea47bd91519b54c134efb4da0d935-1480953600847"=>["presentation"]
      {}.tap{ |r| list.each{ |h| h.each{ |k,v| (r[k]||=[]) << v } } }
    end

    def has_aws_published_on_metadata(metadata_file)
      doc = nil
      begin
        doc = Nokogiri::XML(open(metadata_file).read) { |x| x.noblanks }
      rescue Exception => e
        BigBlueButtonS3.logger.error "Error parsing metadata file, skipping. #{e.inspect}"
        return
      end

      ! doc.at("//meta/bbb-aws-published-time").nil?
    end

    def setup_bucket(bucket_name)
      if ! @s3.bucket(bucket_name).exists?
        BigBlueButtonS3.logger.info "Creating bucket #{bucket_name}"
        @s3.create_bucket(bucket: bucket_name)
      else
        BigBlueButtonS3.logger.info "Bucket #{bucket_name} already exists"
      end
    end

    def fetch_metadata(published_dir, formats, bucket_name)
      opt = {
        bucket: bucket_name,
        max_keys: 1000
      }
      prefix_list = []
      filename_filter = [ "metadata.xml", "metadata.xml.orig" ]
      index = 0
      loop do
        index += 1
        resp = @client.list_objects_v2(opt)
        opt[:continuation_token] = resp.next_continuation_token
        resp_filtered = resp.contents.select{ |obj| filename_filter.include? File.basename(obj.key) }.map{ |obj| obj.key }
        prefix_list += resp_filtered
        break if opt[:continuation_token].nil?
      end
      prefix_list.each_with_index do |key, index|
        target = "#{published_dir}/#{key}"
        if ! File.exists? target
          BigBlueButtonS3.logger.info "Fetching #{index+1}/#{prefix_list.length} #{key}"
          FileUtils.mkdir_p "#{published_dir}/#{File.dirname(key)}"
          @client.get_object({ bucket: bucket_name, key: key }, target: target)

          update_metadata_link(target) if File.basename(target) == "metadata.xml"
        end
      end
    end

    private

    def compare_and_push(remote_prefix, local_dir, parent_dir, bucket_name, set_public, metadata: {})
      success = true

      BigBlueButtonS3.logger.debug "remote_prefix: #{remote_prefix}"
      BigBlueButtonS3.logger.debug "local_dir: #{local_dir}"
      BigBlueButtonS3.logger.debug "parent_dir: #{parent_dir}"

      local_md5 = load_local_md5(remote_prefix, local_dir, parent_dir)
      BigBlueButtonS3.logger.debug "local_md5: #{JSON.pretty_generate(local_md5)}"
      remote_md5 = load_remote_md5(bucket_name, remote_prefix)
      BigBlueButtonS3.logger.debug "remote_md5: #{JSON.pretty_generate(remote_md5)}"
      modified_files = local_md5.delete_if { |k, v| remote_md5.has_key?(k) && remote_md5.dig(k, :md5) == v[:md5] }
      BigBlueButtonS3.logger.debug "modified_files: #{JSON.pretty_generate(modified_files)}"

      if modified_files.empty?
        BigBlueButtonS3.logger.info "No need to push files to AWS"
      else
        success &= upload_files(modified_files, bucket_name, set_public, metadata: metadata)
      end
      success
    end

    def publish_helper(record_id, published_dir, bucket_name, set_public, formats = nil)
      BigBlueButtonS3.logger.info "#{set_public ? "Publishing" : "Unpublishing"} recording #{record_id}"
      prefixes = get_prefixes(record_id, published_dir, formats)
      success = true
      prefixes.each do |prefix|
        local_dir = "#{published_dir}/#{prefix}"

        BigBlueButtonS3.logger.info "Processing prefix #{prefix}"

        # update link on the metadata file
        metadata_file = "#{local_dir}/metadata.xml"
        BigBlueButtonS3.logger.info "Reading #{metadata_file}"
        if ! File.exists?(metadata_file)
          BigBlueButtonS3.logger.info "No metadata found, going to next format..."
          next
        end

        local_success = true

        # add published timestamp to metadata
        # this is also used to check if the redis event has been processed already or not
        add_aws_published_to_metadata(metadata_file) if ! has_aws_published_on_metadata(metadata_file)

        if isset('BBB_AWS_REMOTE_PLAYBACK')
          # update the playback links in the metadata file to use the new domain
          metadata_updated = update_metadata_link(metadata_file)
          if metadata_updated
            BigBlueButtonS3.logger.info "Metadata updated with links to remote playback"
          end
        end

        local_success &= compare_and_push(prefix, local_dir, local_dir, bucket_name, set_public)

        if local_success && ! @keep_local
          Dir.glob("#{local_dir}/**/*").each do |file|
            # do not delete metadata.xml and metadata.xml.orig
            next if File.basename(file).include?("metadata.xml")
            BigBlueButtonS3.logger.info "Removing local file: #{file}"
            FileUtils.rm_rf file
          end
        end
        success &= local_success

        # reset recursively the ownership of the recording dir
        FileUtils.chown_R File.stat(local_dir).uid, File.stat(local_dir).gid, local_dir
      end
      BigBlueButtonS3.logger.info "Recording #{record_id} #{set_public ? "published" : "unpublished"} successfully" if success
      success
    end

    def update_metadata_link(metadata_file)
      backup_metadata(metadata_file)
      doc = nil
      begin
        BigBlueButtonS3.logger.info "Reading the metadata file #{metadata_file}"
        doc = Nokogiri::XML(open(metadata_file).read) { |x| x.noblanks }
      rescue Exception => e
        BigBlueButtonS3.logger.error "Error parsing metadata file, skipping. #{e.inspect}"
        return false
      end

      modified = false

      # bbb-media-url is deprecated
      media_node = doc.at_xpath('//meta/bbb-media-url')
      if ! media_node.nil?
        media_node.remove
        modified = true
      end

      link_node = doc.at_xpath('//playback/link')
      if link_node.nil?
        # ooops, no playback link on metadata, abort
        return false
      end

      original_link_node_name = "bbb-aws-original-link"
      format_node = doc.at_xpath('//playback/format')
      if ! format_node.nil?
        # replace _ by - so meta key is valid
        original_link_node_name += "-#{format_node.content}".gsub('_','-')
        modified = true
      end

      # we always update based on the original link, and we keep it as a metadata
      xml_node = doc.at_xpath("//meta/#{original_link_node_name}")
      if xml_node.nil?
        xml_node = Nokogiri::XML::Node.new original_link_node_name, doc
        xml_node.content = link_node.content
        doc.at("//meta") << xml_node
        modified = true
      end

      # update thumbnail links
      doc.xpath("//playback/extensions/preview/images/image").each do |node|
        old_link = node.content
        new_link = get_modified_link(node.content)
        if new_link != old_link
          node.content = new_link
          modified = true
        end
      end

      old_link = link_node.content
      new_link = get_modified_link(xml_node.content)
      if new_link != old_link
        link_node.content = new_link
        modified = true
      end

      if modified
        metadata_xml = File.new(metadata_file,"w")
        metadata_xml.write(doc.to_xml(:indent => 2))
        metadata_xml.close
      end
      modified
    end

    def add_aws_published_to_metadata(metadata_file)
      backup_metadata(metadata_file)
      doc = nil
      begin
        doc = Nokogiri::XML(open(metadata_file).read) { |x| x.noblanks }
      rescue Exception => e
        BigBlueButtonS3.logger.error "Error parsing metadata file, skipping. #{e.inspect}"
        return
      end

      xml_node = doc.at_xpath("//meta/bbb-aws-published-time")
      if xml_node.nil?
        xml_node = Nokogiri::XML::Node.new "bbb-aws-published-time", doc
        xml_node.content = ""
        doc.at("//meta") << xml_node
      end
      xml_node.content = DateTime.now.strftime('%Q')

      metadata_xml = File.new(metadata_file,"w")
      metadata_xml.write(doc.to_xml(:indent => 2))
      metadata_xml.close
    end

    def backup_metadata(metadata_file)
      if ! File.exists?("#{metadata_file}.orig")
        FileUtils.cp(metadata_file, "#{metadata_file}.orig", :preserve => true)
      end
    end

    def get_formats
      $available_formats
    end

    def get_prefixes(record_id, published_dir, formats = nil)
      formats = get_formats if formats.nil?
      formats.map { |format| "#{format}/#{record_id}" }
    end

    def path_relative_to(path, parent)
      Pathname.new(path).relative_path_from(Pathname.new(parent)).to_s
    end

    def get_users_permission(obj)
      grant = obj.acl.grants.select { |grant| grant.grantee.uri == "http://acs.amazonaws.com/groups/global/AllUsers" }
      grant = grant.length > 0 ? grant.first.permission : nil
      grant
    end

    def load_local_md5(remote_prefix, local_dir, parent_dir)
      BigBlueButtonS3.logger.info "Calculating local md5 from files"
      local_md5 = {}
      if File.file?(local_dir)
        BigBlueButtonS3.logger.info "Single file found at #{local_dir}"
        local_md5[remote_prefix] = {
          :path => local_dir,
          :md5 => `openssl md5 -binary "#{local_dir}" | base64`.strip
        }
      else
        BigBlueButtonS3.logger.info "Read recursively #{local_dir}"
        Dir.glob("#{local_dir}/**/*").each do |file|
          key = File.join(remote_prefix, path_relative_to(file, parent_dir))
          local_md5[key] = {
            :path => file,
            :md5 => `openssl md5 -binary "#{file}" | base64`.strip
          } if File.file?(file)
        end
      end
      local_md5
    end

    def key_exists?(bucket_name, key)
      @s3.bucket(bucket_name).object(key).exists?
    end

    def load_remote_md5(bucket_name, prefix)
      result = {}
      # credential might not have permission to list the bucket in order to reduce privilege
      # if that's the case, proceed to the upload - it might result into uploading more objects than necessary
      begin
        prefix_list = list_objects(prefix, bucket_name)
        result = Hash[ prefix_list.collect { |key| [ key, { :md5 => @s3.bucket(bucket_name).object(key).metadata().dig("content_md5") } ] } ].delete_if { |k, v| v[:md5].nil? }
      rescue Aws::S3::Errors::AccessDenied
        BigBlueButtonS3.logger.info "No permission to list bucket #{bucket_name}, keep going"
      end
      result
    end

    def upload_files(files, bucket_name, set_public, meeting_description: nil, metadata: {})
      re = Regexp.union(DOWNLOAD_PREFIXES)
      success = true
      files.each do |k, v|
        file_key = k
        file_name = v[:path]
        md5 = v[:md5]

        opts = {
          # it's no longer possible to set acl here
          # :acl => set_public ? "public-read" : "private",
          :storage_class => "STANDARD",
          # set as metadata the md5 of the entire file
          :metadata => metadata.merge({
            "content_md5" => md5
          })
        }

        # set proper content type for the files
        mime = MIME::Types.type_for(file_name).first
        # content type might be nil
        if ! mime.nil?
          opts[:content_type] = mime.content_type
        end
        if m = file_key.match(re)
          opts[:content_disposition] = "attachment; filename=\"#{m[:filename]}\""
        end

        obj = @s3.bucket(bucket_name).object(file_key)
        BigBlueButtonS3.logger.info "Uploading #{file_name}"

        local_success = true
        Retriable.retriable(tries: MAX_ATTEMPTS, on_retry: BigBlueButtonS3.print_retry, max_elapsed_time: MAX_ELAPSED_TIME) do
          local_success = obj.upload_file(file_name, opts)
          raise "upload_file returned #{local_success}" unless local_success
        end
        success &= local_success
      end
      success
    end

    def is_object_public?(obj)
      get_users_permission(obj) == "READ"
    end

    def set_acl(bucket_name, prefix, set_public)
      permission = set_public ? "public-read" : "private"
      success = true
      get_objects(bucket_name, prefix).each do |obj|
        next if set_public == is_object_public?(obj) # skip if acl is already properly set
        BigBlueButtonS3.logger.info "Setting #{obj.key} to #{permission}"
        obj.acl.put({
          acl: permission
        })
        local_success = ( set_public == is_object_public?(obj) )
        BigBlueButtonS3.logger.error "Failed while setting #{obj.key} to #{permission}" if ! local_success
        success &= local_success
      end
      success
    end

    def get_objects(bucket_name, prefix)
      @s3.bucket(bucket_name).objects(prefix: prefix)
    end

    def move_prefix(bucket_name, from_prefix, to_prefix)
      BigBlueButtonS3.logger.info "Moving prefix #{from_prefix} to #{to_prefix}"
      get_objects(bucket_name, from_prefix).each do |obj|
        from_key = obj.key
        # if first character isn't the delimiter, it means that we're iterating over the objects already moved
        next if from_key.sub(from_prefix, "").chr != "/"

        to_key = from_key.sub(from_prefix, to_prefix)
        BigBlueButtonS3.logger.info "Moving #{from_key} to #{to_key}"
        obj.move_to({:bucket => bucket_name, :key => to_key})
      end
      # that would be a way to check if the files were moved properly
      # however it looks like it's retrieving out of date information
      # from_dir = @client.list_objects({
      #   bucket: bucket_name,
      #   prefix: from_prefix,
      #   max_keys: 1000
      # })
      # success = from_dir.contents.length == 0
      # if success
      #   BigBlueButtonS3.logger.info "Moved files successfully"
      # else
      #   BigBlueButtonS3.logger.error "Original directory isn't empty, remaining #{from_dir.contents.length} objects"
      # end
      # success
      # TODO find a way to determine if move was successful or not
      true
    end
  end
end

def record_id_to_timestamp(r)
  r.split("-")[1].to_i / 1000
end

def path_to_record_id(r)
  File.basename(r)
end

def path_to_timestamp(r)
  record_id_to_timestamp(path_to_record_id(r))
end

def isset(name)
  ENV[name] && ENV[name] != '0' && ENV[name].strip != ''
end
