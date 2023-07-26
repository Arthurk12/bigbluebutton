#!/bin/bash

if [ $(command -v redis-cli) == "" ]; then
  echo "Missing redis-cli"
  exit
fi

STATUS_DIR=/var/bigbluebutton/recording/status
RECORDED_DIR=$STATUS_DIR/recorded
ENDED_DIR=$STATUS_DIR/ended
RECORD_STATUS_EVENT="RecordStatusEvent"

isRecorded() {
  meetingId=$1
  key=$2
  recordingEventsNumber=$3

  recorded=-1
  if [ "$(redis-cli hget ${key} record)" == "true" ]; then
    echo "Session has been created with record=true"
    for eventId in $(redis-cli lrange meeting:${meetingId}:recordings 0 ${recordingEventsNumber} | cut -d'"' -f2); do
      eventName=$(redis-cli hget recording:${meetingId}:${eventId} eventName)
      if [ "${eventName}" == $RECORD_STATUS_EVENT ]; then
        echo "Found RecordStatusEvent for meeting ${meetingId}"
        recorded=0
        break
      fi
    done
  fi
  return $recorded
}

hasTag() {
  for file in "$RECORDED_DIR"/*; do
    if [ "$(echo $file | grep ${1})" != "" ]; then
      return 0
    fi
  done
  return -1
}

hasEndedTag() {
  for file in "$ENDED_DIR"/*; do
    if [ "$(echo $file | grep ${1})" != "" ]; then
      return 0
    fi
  done
  return -1
}

echo "Collecting redis meeting info"
KEYS=$(redis-cli keys "meeting:info:*")
echo -e "Meetings found in redis are:\n${KEYS}"

for key in $KEYS; do
  meetingId=$(echo $key | cut -d ':' -f 3)

  echo "--------Processing meeting ${meetingId}--------"

  recordingEventsNumber=$(redis-cli llen meeting:${meetingId}:recordings | cut -d' ' -f2)
  if [ "${recordingEventsNumber}" == "0" ]; then
    echo "No events stored for ${meetingId}"
    echo "-----------------------------------------------------------------------------------------"
    continue
  fi

  isRecorded $meetingId $key $recordingEventsNumber; if [ $? == 0 ]; then
    echo "The meeting ${meetingId} is recorded"
    hasTag $meetingId; if [ $? != 0 ]; then
      echo "Creating recorded done tag for meeting ${meetingId}"
      touch ${RECORDED_DIR}/${meetingId}.done
    fi
  else
    hasTag $meetingId; if [ $? != 0 ]; then
      echo "Creating non-recorded tag for meeting ${meetingId}"
      touch ${RECORDED_DIR}/${meetingId}.norecord
    fi
  fi

  hasEndedTag $meetingId; if [ $? != 0 ]; then
    echo "Creating ended done tag for meeting ${meetingId}"
    touch ${ENDED_DIR}/${meetingId}.done
  fi
  echo "-----------------------------------------------------------------------------------------"
done
