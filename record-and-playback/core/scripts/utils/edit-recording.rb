# encoding: UTF-8

require 'date'
require 'fileutils'
require 'json'
require 'nokogiri'
require 'optimist'
require 'tz'

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

def timestamp_to_date(ms)
    DateTime.strptime(ms.to_s,'%Q')
end

def format_date_time(d, timezone_s = nil)
    timezone_s ||= $timezone
    timezone = TZInfo::Timezone.get(timezone_s)
    local_date = timezone.utc_to_local(d)
    local_date.strftime("%d/%m/%Y %H:%M:%S")
end

def format_time(d, timezone_s = nil)
    timezone_s ||= $timezone
    timezone = TZInfo::Timezone.get(timezone_s)
    local_date = timezone.utc_to_local(d)
    local_date.strftime("%H:%M:%S")
end

def seconds_to_duration(t)
    Time.at(t).utc.strftime("%H:%M:%S")
end

def get_events_from_doc(doc)
  events = []
  ( doc.xpath("/recording/event[1]") + doc.xpath("/recording/event[@module='PARTICIPANT' and @eventname='RecordStatusEvent']") + doc.xpath("/recording/event[last()]") ).sort_by{ |node| node.at_xpath("@timestamp").text.to_i }.each do |node|
      # puts JSON.pretty_generate(events)

      event_module = node.at_xpath("@module").text
      event_name = node.at_xpath("@eventname").text
      timestamp = node.at_xpath("@timestamp").text.to_i
      timestamp_utc = node.at_xpath("timestampUTC").text.to_i
      date_utc = timestamp_to_date(timestamp_utc)

      event = {
          :timestamp => timestamp,
          :timestamp_utc => timestamp_utc,
          :date => date_utc,
          :node => node
      }

      if event_name == "RecordStatusEvent"
          status = node.at_xpath("status").text == "true"
          if status
              event[:type] = :start

              events.pop if ! events.empty? and events.last[0][:type] == :begin

              events << [ event ]
          else
              record_duration_sec = events.length == 1 ? 0 : events[-2].last[:record_duration_sec]
              record_duration_sec += ( ( date_utc - events.last[0][:date] ) * 24 * 60 * 60 ).to_i
              event[:record_duration_sec] = record_duration_sec
              event[:record_duration] = seconds_to_duration(record_duration_sec)
              event[:type] = :stop

              events.last << event
          end
      else
          if events.empty?
              event[:type] = :begin

              events << [ event ]
          elsif events.last.length < 2
              record_duration_sec = events.length == 1 ? 0 : events[events.length - 2][:record_duration_sec]
              record_duration_sec += ( ( date_utc - events.last[0][:date] ) * 24 * 60 * 60 ).to_i
              event[:record_duration_sec] = record_duration_sec
              event[:record_duration] = seconds_to_duration(record_duration_sec)
              event[:type] = :last

              events.last << event
          end
      end
  end
  [ doc, events ]
end

def get_events_from_file(events_xml)
    doc = Nokogiri::XML(File.open(events_xml)) { |x| x.noblanks }
    get_events_from_doc(doc)
end

def print(doc, events)
    puts "Begin at: #{format_time(timestamp_to_date(doc.xpath("/recording/event[1]").first.at_xpath('timestampUTC').text.to_i))}"
    events.each_with_index do |event, idx|
        puts "#{idx}: #{format_time(event[0][:date])} -> #{format_time(event[1][:date])} (#{idx == 0 ? '00:00:00' : events[idx - 1][1][:record_duration]} -> #{event[1][:record_duration]})"
        # puts JSON.pretty_generate(event)
    end
    puts "End at: #{format_time(timestamp_to_date(doc.xpath("/recording/event[last()]").first.at_xpath('timestampUTC').text.to_i))}"
end

def add_node(doc, time, status)
  time = DateTime.strptime(time, '%H:%M:%S')

  first_node = doc.xpath("/recording/event[1]").first
  first_timestamp_utc = first_node.at_xpath("timestampUTC").text.to_i
  first_timestamp = first_node.at_xpath("@timestamp").text.to_i
  first_node_offset = DateTime.strptime(first_node.at_xpath("date").text, '%Y-%m-%dT%H:%M:%S.%L%z').offset
  date_utc = timestamp_to_date(first_timestamp_utc)

  tz = TZInfo::Timezone.get($timezone)
  tz_offset = tz.utc_offset / 3600

  datetime = DateTime.new(date_utc.year, date_utc.month, date_utc.day, time.hour, time.minute, time.second, Rational(tz_offset,24))

  timestamp_utc = datetime.strftime("%Q").to_i
  timestamp = timestamp_utc - first_timestamp_utc + first_timestamp
  date = datetime.new_offset(first_node_offset).strftime("%Y-%m-%dT%H:%M:%S.%L%z")

  node = <<EOT
<event timestamp="#{timestamp}" module="PARTICIPANT" eventname="RecordStatusEvent">
  <timestampUTC>#{timestamp_utc}</timestampUTC>
  <date>#{date}</date>
  <status>#{status}</status>
  <userId>SYSTEM</userId>
</event>
EOT

  doc.xpath("/recording/event[@timestamp <= #{timestamp}]").last.add_next_sibling(node)
end

# this is required to blank spaces are properly removed from the document
def reload(doc)
  Nokogiri::XML(doc.to_xml) { |x| x.noblanks }
end

def save(doc, events_xml)
  FileUtils.cp events_xml, "#{events_xml}.orig" if ! File.exists? "#{events_xml}.orig"
  xml_file = File.new(events_xml, "w")
  xml_file.write(doc.to_xml(:indent => 2))
  xml_file.close
end

opts = Optimist::options do
    opt :events_xml, "Path to events.xml", :type => String, :required => true
    opt :timezone, "Timezone", :type => String, :required => false, :default => "America/Sao_Paulo"
    opt :operation, "Operation [add|remove|modify|print]", :type => String, :default => "print"
    opt :data, "Data, example '13:28:26-13:28:35'", :type => String
end

events_xml = opts[:events_xml]
$timezone = opts[:timezone]

doc, events = get_events_from_file(events_xml)

case opts[:operation]
when "add"
  start, stop = opts[:data].split("-")
  start_node = add_node(doc, start, "true")
  stop_node = add_node(doc, stop, "false")
  doc = reload(doc)

  save(doc, events_xml)
when "remove"
  opts[:data].split(",").each do |idx|
    segment = events[idx.to_i]
    segment.each do |event|
      event[:node].remove
    end
  end

  save(doc, events_xml)
when "print"
  print(doc, events)
when "modify"
  raise "not implemented"
end
