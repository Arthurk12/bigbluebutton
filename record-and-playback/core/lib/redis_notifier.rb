# encoding: UTF-8

require 'json'
require 'logger'
require 'net/http'
require 'uri'

require "#{File.dirname(__FILE__)}/recordandplayback"

class RedisNotifier
  MAX_ATTEMPT = 20

  def initialize(host:, port:, password:, ssl:)
    BigBlueButton.redis_publisher = BigBlueButton::RedisWrapper.new(host, port, password, ssl)
  end

  def logger=(log)
    @logger = log
  end

  def logger
    return @logger if @logger
    logger = Logger.new(STDOUT)
    logger.level = Logger::INFO
    @logger = logger
  end

  def sanity_ended(record_id, internal_meeting_id, external_meeting_id)
    # do nothing
  end

  def process_started(record_id, internal_meeting_id, external_meeting_id, workflow)
    # record_id is discovered events_archiver.rb
    BigBlueButton.redis_publisher.put_process_started(workflow, internal_meeting_id)
  end

  def process_ended(record_id, internal_meeting_id, external_meeting_id, workflow, step_succeeded, step_time)
    # record_id is discovered events_archiver.rb
    BigBlueButton.redis_publisher.put_process_ended(workflow, internal_meeting_id, {
      "success" => step_succeeded,
      "step_time" => step_time
    })
  end

  def publish_started(record_id, internal_meeting_id, external_meeting_id, workflow)
    # record_id is discovered events_archiver.rb
    BigBlueButton.redis_publisher.put_publish_started(workflow, internal_meeting_id)
  end

  def publish_ended(record_id, internal_meeting_id, external_meeting_id, workflow, step_succeeded, step_time, payload)
    # record_id is discovered events_archiver.rb
    BigBlueButton.redis_publisher.put_publish_ended(workflow, internal_meeting_id, payload)
  end
end
