# encoding: UTF-8

require 'elasticsearch'
require 'json'
require 'logger'
require 'net/http'
require 'retriable'
require 'uri'

class ElasticsearchNotifier
  MAX_ATTEMPT = 20

  def initialize(host:, path:, port:, user:, password:, scheme:)
    @elastic = Elasticsearch::Client.new hosts: [
      { host: host,
        path: String.new(path),
        port: port,
        user: user,
        password: password,
        scheme: scheme }
    ], log: true, retry_on_failure: MAX_ATTEMPT, request_timeout: 30
    @document = Hash.new
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

  def get_document(internal_meeting_id)
    return @document[internal_meeting_id] if @document.has_key? internal_meeting_id
    @document[internal_meeting_id] = search_document(internal_meeting_id)
    @document[internal_meeting_id]
  end

  def sanity_ended(record_id, internal_meeting_id, external_meeting_id)
    # do nothing
  end

  def process_started(record_id, internal_meeting_id, external_meeting_id, workflow)
    # TODO use different index to store recordings
    return if record_id != internal_meeting_id

    doc = get_document(internal_meeting_id)
    if doc.nil?
      logger.warn "No document found on Elastic for internal_meeting_id #{internal_meeting_id}"
      return
    end

    post(doc, "process_started", workflow)
  end

  def process_ended(record_id, internal_meeting_id, external_meeting_id, workflow, step_succeeded, step_time)
    # TODO use different index to store recordings
    return if record_id != internal_meeting_id

    doc = get_document(internal_meeting_id)
    if doc.nil?
      logger.warn "No document found on Elastic for internal_meeting_id #{internal_meeting_id}"
      return
    end

    post(doc, "process_ended", workflow)
  end

  def publish_started(record_id, internal_meeting_id, external_meeting_id, workflow)
    # TODO use different index to store recordings
    return if record_id != internal_meeting_id

    doc = get_document(internal_meeting_id)
    if doc.nil?
      logger.warn "No document found on Elastic for internal_meeting_id #{internal_meeting_id}"
      return
    end

    post(doc, "publish_started", workflow)
  end

  def publish_ended(record_id, internal_meeting_id, external_meeting_id, workflow, step_succeeded, step_time, payload)
    # TODO use different index to store recordings
    return if record_id != internal_meeting_id

    doc = get_document(internal_meeting_id)
    if doc.nil?
      logger.warn "No document found on Elastic for internal_meeting_id #{internal_meeting_id}"
      return
    end

    post(doc, "publish_ended", workflow)
  end

  private

  def timestamp
    Time.now.to_i
  end

  def search_document(internal_meeting_id)
    index = ENV['MCONF_REC_NOTIFIER_ELASTIC_INDEX']
    body = {
      "query": {
        "bool": {
          "must": [],
          "filter": [
            {
              "match_all": {}
            }
          ],
          "should": [],
          "must_not": []
        }
      }
    }

    case index
    when "summary-*"
      body[:query][:bool][:filter] += [
        {
          "match_phrase": {
            "internal_meeting_id.keyword": {
              "query": internal_meeting_id
            }
          }
        },
        {
          "match_phrase": {
            "type.keyword": {
              "query": "meeting"
            }
          }
        }
      ]
    when "summary-meeting-*"
      body[:query][:bool][:filter] += [
        {
          "match_phrase": {
            "internal_meeting_id": {
              "query": internal_meeting_id
            }
          }
        }
      ]
    else
      return nil
    end

    results = nil
    begin
      results = @elastic.search(index: index, body: body)
    rescue Exception => e
      logger.warn "Failed to search document #{internal_meeting_id} on ElasticSearch"
      return nil
    end

    found = results.dig("hits", "total", "value").to_i
    result = results.dig("hits", "hits", 0)
    if found > 0
      return {
        id: result["_id"],
        index: result["_index"],
      }
    end
    return nil
  end

  def post(doc, step, workflow)
    body = {
      "doc": {
        "#{step}_#{workflow}": timestamp,
        "latest_record_event": "#{step}_#{workflow}"
      }
    }
    body[:doc]["batch_#{workflow}_job_id".to_sym] = ENV['AWS_BATCH_JOB_ID'] unless ENV['AWS_BATCH_JOB_ID'].nil? or ENV['AWS_BATCH_JOB_ID'].length == 0
    body[:doc]["batch_#{workflow}_job_attempt".to_sym] = ENV['AWS_BATCH_JOB_ATTEMPT'] unless ENV['AWS_BATCH_JOB_ATTEMPT'].nil? or ENV['AWS_BATCH_JOB_ATTEMPT'].length == 0

    Retriable.retriable(tries: MAX_ATTEMPT, on_retry: @print_retry, max_elapsed_time: 1800) do
      @elastic.update index: doc[:index], id: doc[:id], retry_on_conflict: 5, body: body
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
