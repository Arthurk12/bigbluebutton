#!/bin/bash

if [ $(command -v redis-cli) == "" ]; then
  echo "Missing redis-cli"
  exit
fi

STATUS_DIR=/var/bigbluebutton/recording/status
RECORDED_DIR=$STATUS_DIR/recorded
ENDED_DIR=$STATUS_DIR/ended

isRecorded() {
  if [ "$(echo $@ | grep "record true")" != "" ]; then
    return 0
  else
    return -1
  fi
}

hasRecordedTag() {
  for file in "$RECORDED_DIR"/*; do
    if [ "$(echo $file | grep $1)" != "" ]; then
      return 0
    fi
  done
  return -1
}

hasEndedTag() {
  for file in "$ENDED_DIR"/*; do
    if [ "$(echo $file | grep $1)" != "" ]; then
      return 0
    fi
  done
  return -1
}

echo "Collecting redis meeting info"
KEYS=$(redis-cli keys "meeting:info:*")

for key in $KEYS; do
  meetingId=$(echo $key | cut -d ':' -f 3)
  info=$(redis-cli hgetall $key)
  isRecorded $info; if [ $? == 0 ]; then
    hasRecordedTag $meetingId; if [ $? != 0 ]; then
      echo "Creating recorded done tag for meeting $meetingId"
      touch $RECORDED_DIR/$meetingId".done"
    fi
  fi
  hasEndedTag $meetingId; if [ $? != 0 ]; then
    echo "Creating ended done tag for meeting $meetingId"
    touch $ENDED_DIR/$meetingId".done"
  fi
done
