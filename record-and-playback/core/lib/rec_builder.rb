require 'aws-sdk-core'
require 'yaml'
require 'wisper'

require "#{File.dirname(__FILE__)}/bigbluebutton_s3"
require "#{File.dirname(__FILE__)}/recordandplayback"
require "#{File.dirname(__FILE__)}/elasticsearch_notifier"
require "#{File.dirname(__FILE__)}/redis_notifier"
require "#{File.dirname(__FILE__)}/webhook_notifier"

class RecordingBuilder
  include Wisper::Publisher

  def initialize
    if ENV['MCONF_REC_NOTIFIER_WEBHOOK_ENABLED'] == "1"
      @webhook = WebhookNotifier.new(
        uri: ENV['MCONF_REC_NOTIFIER_WEBHOOK_URI'],
        bearer_auth: ENV['MCONF_REC_NOTIFIER_WEBHOOK_BEARER_AUTH'],
        domain: ENV['MCONF_REC_NOTIFIER_WEBHOOK_DOMAIN'],
      )
      @webhook.logger = logger
      subscribe(@webhook)
    end

    if ENV['MCONF_REC_NOTIFIER_ELASTIC_ENABLED'] == "1"
      @elastic = ElasticsearchNotifier.new(
        host: ENV['MCONF_REC_NOTIFIER_ELASTIC_HOST'],
        path: ENV['MCONF_REC_NOTIFIER_ELASTIC_PATH'],
        port: ENV['MCONF_REC_NOTIFIER_ELASTIC_PORT'],
        user: ENV['MCONF_REC_NOTIFIER_ELASTIC_AUTH_USER'],
        password: ENV['MCONF_REC_NOTIFIER_ELASTIC_AUTH_PASS'],
        scheme: ENV['MCONF_REC_NOTIFIER_ELASTIC_SCHEME'],
      )
      @elastic.logger = logger
      subscribe(@elastic)
    end

    if ENV['MCONF_REC_NOTIFIER_REDIS_ENABLED'] == "1"
      @redis = RedisNotifier.new(
        host: ENV['MCONF_REC_NOTIFIER_REDIS_HOST'],
        port: ENV['MCONF_REC_NOTIFIER_REDIS_PORT'],
        password: ENV['MCONF_REC_NOTIFIER_REDIS_PASSWORD'],
        ssl: ENV['MCONF_REC_NOTIFIER_REDIS_SSL'],
      )
      subscribe(@redis)
    end

    @rebuild = true
    @downloaded_raw = false
  end

  def logger=(log)
    @logger = log
    BigBlueButtonS3::logger = log
    @redis.logger = log if @redis
    @webhook.logger = log if @webhook
    @elastic.logger = log if @elastic
  end

  def logger
    return @logger if @logger
    logger = Logger.new(STDOUT)
    logger.level = Logger::INFO
    @logger = logger
  end

  def load_publisher(env_prefix)
    key = ENV["#{env_prefix}_ACCESS_KEY_ID"] || ""
    secret = ENV["#{env_prefix}_SECRET_ACCESS_KEY"] || ""
    endpoint = ENV["#{env_prefix}_ENDPOINT"]
    region = ENV["#{env_prefix}_REGION"]
    bucket = ENV["#{env_prefix}_NAME"]
    [ BigBlueButtonS3::Publisher.new(key: key, secret: secret, region: region, endpoint: endpoint), ENV["#{env_prefix}_NAME"] ]
  end

  def perform(record_id)
    ENV['MCONF_REC_WORKER_FORMAT'].split(',').each{ |format| perform_helper(record_id, format) }

    tag_raw(record_id) if @downloaded_raw

    true
  end

  def perform_helper(record_id, process_type)
    props = YAML::load(File.open('bigbluebutton.yml'))
    published_dir = props['published_dir']
    recording_dir = props['recording_dir']

    target_dir = "#{published_dir}/#{process_type}/#{record_id}"
    processed_done = "#{recording_dir}/status/processed/#{record_id}-#{process_type}.done"
    published_done = "#{recording_dir}/status/published/#{record_id}-#{process_type}.done"
    raw_dir = "#{recording_dir}/raw/#{record_id}"

    if ! @rebuild and Dir.exists?(target_dir)
      # no need to rebuild and recording is published
      return
    end

    if ! Dir.exists?(raw_dir)
      if ! isset('MCONF_REC_WORKER_AWS_S3_BUCKET_UPLOAD_NAME')
        raise "Raw files are missing and MCONF_REC_WORKER_AWS_S3_BUCKET_UPLOAD_NAME is not set"
      end

      # download it
      publisher, bucket_upload = load_publisher("MCONF_REC_WORKER_AWS_S3_BUCKET_UPLOAD")
      success = publisher.download_raw(record_id, bucket_upload, "#{recording_dir}/raw")
      raise "Cannot find raw files for #{record_id} on the object storage" if ! success
      @downloaded_raw = true
    end

    # cleanup
    FileUtils.rm_rf target_dir
    Dir["#{recording_dir}/status/processed/*-#{process_type}.*",
        "#{recording_dir}/status/published/*-#{process_type}.*",
        "#{recording_dir}/process/#{process_type}/#{record_id}",
        "#{recording_dir}/publish/#{process_type}/#{record_id}"].each{ |file| FileUtils.rm_rf file }

    events_xml = "#{recording_dir}/raw/#{record_id}/events.xml"
    if ! File.exists?(events_xml)
      raise "Cannot find events.xml for #{record_id}"
    end

    # TODO use metadata from API, so it could be checked before download the raw
    metadata = BigBlueButton::Events.get_meeting_metadata(events_xml)
    if metadata.has_key?("#{process_type}-playback-enabled")
      if metadata["#{process_type}-playback-enabled"].to_s == "false"
        logger.info("Format #{process_type} skipped due to metadata")
        return
      end
    else
      # only consider default config if metadata is not set
      if ENV["MCONF_REC_WORKER_FORMAT_#{process_type.upcase}_ENABLED"].to_s == "false"
        logger.info("Format #{process_type} skipped due to default configuration")
        return
      end
    end

    @external_meeting_id = BigBlueButton::Events.get_external_meeting_id(events_xml)
    @internal_meeting_id = BigBlueButton::Events.get_internal_meeting_id(events_xml)

    xml_doc = Nokogiri::XML(File.open(events_xml)) { |x| x.noblanks }

    # notify aggr if entry in the recordings table doesn't exist
    broadcast(:sanity_ended, record_id, @internal_meeting_id, @external_meeting_id)

    step_succeeded = process(recording_dir, record_id, process_type)
    raise "Failed to process #{process_type}, record_id=#{record_id}" if ! step_succeeded
    step_succeeded = publish(recording_dir, record_id, process_type)
    raise "Failed to publish #{process_type}, record_id=#{record_id}" if ! step_succeeded

    transcription_obj = {
      :enabled => false
    }

    # TODO improve this, so transcription is copied to all formats
    if process_type == "presentation" and should_transcribe?(target_dir)
      broadcast(:transcription_started, record_id, @internal_meeting_id, @external_meeting_id)
      step_start_time = BigBlueButton.monotonic_clock

      ret = nil
      if ENV["MCONF_REC_WORKER_LOG_STDOUT"] == "1"
        ret = BigBlueButton.exec_ret("ruby", "transcribe/transcribe.rb", "-m", record_id, "--log-stdout")
      else
        ret = BigBlueButton.exec_ret("ruby", "transcribe/transcribe.rb", "-m", record_id)
      end
      step_succeeded = (ret == 0)

      step_stop_time = BigBlueButton.monotonic_clock
      step_time = step_stop_time - step_start_time

      transcription_obj = {
        :enabled => true,
        :step_succeeded => step_succeeded,
        :step_time => step_time
      }

      # delay transcription_ended until the files are uploaded to the complete bucket
    end

    if isset("MCONF_REC_WORKER_AWS_S3_BUCKET_COMPLETE_NAME")
      publisher, bucket_complete = load_publisher("MCONF_REC_WORKER_AWS_S3_BUCKET_COMPLETE")
      publisher.keep_local = true

      success = publisher.publish(record_id, published_dir, bucket_complete, [ process_type ])
      raise "Failed to upload format #{process_type} to bucket, record_id=#{record_id}" if ! success
    end

    # only triggers transcription_ended after uploading the files to complete bucket
    if transcription_obj[:enabled]
      broadcast(:transcription_ended, record_id, @internal_meeting_id, @external_meeting_id, transcription_obj[:step_succeeded], transcription_obj[:step_time])
    end
  end

  private

  def should_transcribe?(target_dir)
    # check if env enable transcribe
    if ENV["MCONF_REC_WORKER_TRANSCRIBE_ENABLED"] != "true"
      BigBlueButton.logger.info("Do not transcribe because MCONF_REC_WORKER_TRANSCRIBE_ENABLED=false")
      return false
    end

    # check if metadata.xml exists
    metadata_xml = "#{target_dir}/metadata.xml"
    metadata = Nokogiri::XML(File.open(metadata_xml)) { |x| x.noblanks }
    if ! File.exists?(metadata_xml)
      BigBlueButton.logger.info("Do not transcribe because metadata was not found")
      return false
    end

    # merge env with transcribe.yml
    props_file = File.expand_path('../../scripts/transcribe/transcribe.yml', __FILE__)
    if ! File.exists?(props_file)
      BigBlueButton.logger.info("Do not transcribe because transcribe.yml was not found")
      return false
    end
    props = YAML::load(File.open(props_file))
    if BigBlueButton.isset("MCONF_REC_CUSTOM_TRANSCRIBE_YML_B64")
      override_props = YAML::load(Base64.decode64(ENV["MCONF_REC_CUSTOM_TRANSCRIBE_YML_B64"]))
      props.merge!(override_props)
    end

    # test matcher
    props['matcher'].each do |item|
      BigBlueButton.logger.info("Testing if #{item['xpath']}=#{item['value']}")

      node = metadata.at_xpath(item['xpath'])

      if ! node.nil? && node.text == item['value']
        return true
      end
    end
    BigBlueButton.logger.info("Do not transcribe because no match was found")
    return false
  end

  def tag_raw(record_id)
    # OCI doesn't support tagging
    return if ENV['MCONF_REC_WORKER_AWS_S3_TAGGING_SUPPORTED'] == "false"

    # only tag raw if the published content was pushed to s3
    if isset("MCONF_REC_WORKER_AWS_S3_BUCKET_COMPLETE_NAME")
      publisher, bucket_upload = load_publisher("MCONF_REC_WORKER_AWS_S3_BUCKET_UPLOAD")
      success = publisher.tag_raw(record_id, bucket_upload)
      raise "Cannot tag raw file as completed for #{record_id}" if ! success
    end
  end

  def isset(name)
    ENV[name] && ENV[name] != '0' && ENV[name].strip != ''
  end

  def process(recording_dir, record_id, process_type)
    processed_done = "#{recording_dir}/status/processed/#{record_id}-#{process_type}.done"

    broadcast(:process_started, record_id, @internal_meeting_id, @external_meeting_id, process_type)

    step_start_time = BigBlueButton.monotonic_clock

    ret = nil
    script_file = "#{process_type}.rb"
    if ENV["MCONF_REC_WORKER_LOG_STDOUT"] == "1"
      ret = BigBlueButton.exec_ret("ruby", "process/#{script_file}", "-m", record_id, "--log-stdout")
    else
      ret = BigBlueButton.exec_ret("ruby", "process/#{script_file}", "-m", record_id)
    end
    step_succeeded = (ret == 0 and File.exists?(processed_done))
    raise "Failed to process #{process_type}" if ! step_succeeded

    step_stop_time = BigBlueButton.monotonic_clock
    step_time = step_stop_time - step_start_time

    broadcast(:process_ended, record_id, @internal_meeting_id, @external_meeting_id, process_type, step_succeeded, step_time)

    return step_succeeded
  end

  def publish(recording_dir, record_id, process_type)
    published_done = "#{recording_dir}/status/published/#{record_id}-#{process_type}.done"

    broadcast(:publish_started, record_id, @internal_meeting_id, @external_meeting_id, process_type)

    step_start_time = BigBlueButton.monotonic_clock

    ret = nil
    script_file = "#{process_type}.rb"
    if ENV["MCONF_REC_WORKER_LOG_STDOUT"] == "1"
      ret = BigBlueButton.exec_ret("ruby", "publish/#{script_file}", "-m", "#{record_id}-#{process_type}", "--log-stdout")
    else
      ret = BigBlueButton.exec_ret("ruby", "publish/#{script_file}", "-m", "#{record_id}-#{process_type}")
    end
    step_succeeded = (ret == 0 and File.exists?(published_done))
    raise "Failed to publish #{process_type}" if ! step_succeeded

    step_stop_time = BigBlueButton.monotonic_clock
    step_time = step_stop_time - step_start_time

    metadata_path = "/var/bigbluebutton/published/#{process_type}/#{record_id}/metadata.xml"
    doc = Hash.from_xml(File.open(metadata_path))
    playback = doc.dig(:recording, :playback) || {}
    # submit publish time to the webhook
    playback[:publish_time] = (Time.now.to_f * 1000).round

    xml_doc = Nokogiri::XML(File.open(metadata_path)) { |x| x.noblanks }
    playback[:extensions][:preview][:images][:image] = [ playback[:extensions][:preview][:images][:image] ] if xml_doc.xpath("/recording/playback/extensions/preview/images/image").size == 1

    payload = JSON.parse({
      "success" => step_succeeded,
      "step_time" => step_time,
      "playback" => playback,
      "metadata" => BigBlueButton.get_metadata_from_recording(doc[:recording]),
      "download" => doc.dig(:recording, :download) || {},
      "raw_size" => doc.dig(:recording, :raw_size) || {},
      "start_time" => doc.dig(:recording, :start_time) || {},
      "end_time" => doc.dig(:recording, :end_time) || {}
    }.to_json)

    broadcast(:publish_ended, record_id, @internal_meeting_id, @external_meeting_id, process_type, step_succeeded, step_time, payload)

    return step_succeeded
  end
end
