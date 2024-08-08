# encoding: UTF-8

require 'json'
require 'logger'
require 'net/http'
require 'retriable'
require 'uri'

class WebhookNotifier
  MAX_ATTEMPT = 20

  def initialize(uri:, bearer_auth:, domain:)
    @post_uri = URI.parse(uri)
    @post_http = Net::HTTP.new(@post_uri.host, @post_uri.port)
    @post_http.read_timeout = 10
    @post_http.use_ssl = true
    @post_headers = {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Authorization': "Bearer #{bearer_auth}"
    }
    @post_body_domain = domain
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
    id = 'rap-sanity-ended'
    event = {
      "data" => {
        "type" => "event",
        "id" => id,
        "attributes" => {
          "meeting" => {
            "internal-meeting-id" => internal_meeting_id,
            "external-meeting-id" => external_meeting_id
          },
          "record-id" => record_id,
          "success" => true,
          "step-time" => 0
        },
        "event" => {
          "ts" => Time.now.to_i
        }
      }
    }
    post(event)
  end

  def process_started(record_id, internal_meeting_id, external_meeting_id, workflow)
    id = 'rap-process-started'
    event = get_base_event(id, record_id, internal_meeting_id, external_meeting_id, workflow)
    post(event)
  end

  def process_ended(record_id, internal_meeting_id, external_meeting_id, workflow, step_succeeded, step_time)
    id = 'rap-process-ended'
    event = get_base_event(id, record_id, internal_meeting_id, external_meeting_id, workflow)
    event["data"]["attributes"]["success"] = step_succeeded
    event["data"]["attributes"]["step-time"] = step_time
    post(event)
  end

  def publish_started(record_id, internal_meeting_id, external_meeting_id, workflow)
    id = 'rap-publish-started'
    event = get_base_event(id, record_id, internal_meeting_id, external_meeting_id, workflow)
    post(event)
  end

  def publish_ended(record_id, internal_meeting_id, external_meeting_id, workflow, step_succeeded, step_time, payload)
    id = 'rap-publish-ended'
    event = get_base_event(id, record_id, internal_meeting_id, external_meeting_id, workflow)
    event["data"]["attributes"]["success"] = step_succeeded
    event["data"]["attributes"]["step-time"] = step_time

    event["data"]["attributes"]["recording"] = {
      "name" => payload["metadata"]["meetingName"],
      "is-breakout" => payload["metadata"]["isBreakout"],
      "start-time" => payload["start_time"],
      "end-time" => payload["end_time"],
      "size" => payload["playback"]["size"],
      "raw-size" => payload["raw_size"],
      "metadata" => payload["metadata"],
      "playback" => payload["playback"],
      "download" => payload["download"]
    }

    post(event)
  end

  private

  def get_base_event(id, record_id, internal_meeting_id, external_meeting_id, workflow)
    event = {
      "data" => {
        "type" => "event",
        "id" => id,
        "attributes" => {
          "meeting" => {
            "internal-meeting-id" => internal_meeting_id,
            "external-meeting-id" => external_meeting_id
          },
          "record-id" => record_id,
          "workflow" => workflow
        },
        "event" => {
          "ts" => Time.now.to_i
        }
      }
    }

    event
  end

  def get_timestamp(now)
    # TODO: Somehow the webhook timestamp gets a string value.
    # Copied that behavior here...
    (now.to_f * 1000).round.to_s
  end

  def post(event)
    logger.info "Posting to #{@post_uri.to_s} event #{event.to_json}"
    request = Net::HTTP::Post.new(@post_uri.request_uri, @post_headers)
    data = {
      event: "[#{event.to_json}]",
      timestamp: get_timestamp(Time.now),
      domain: @post_body_domain
    }
    request.set_form_data(data)

    Retriable.retriable(tries: MAX_ATTEMPT, on_retry: @print_retry, max_elapsed_time: 1800) do
      response = @post_http.request(request)
      raise "Response to #{@post_uri.request_uri} was #{response.code} - #{response.msg}" unless response.kind_of? Net::HTTPSuccess

      status = JSON.parse(response.body)["status"]
      raise "Status of response was #{status} - #{response.body}" unless status == "Success"
    end
  end

  def print_retry
    return @print_retry if @print_retry
    @print_retry = Proc.new do |exception, try, elapsed_time, next_interval|
      msg = "Attempt #{try} failed due to #{exception.class}: '#{exception.message}'"
      msg += " - trying again in #{next_interval.round(1)} seconds" unless next_interval.nil?
      logger.warn msg
    end
  end
end
