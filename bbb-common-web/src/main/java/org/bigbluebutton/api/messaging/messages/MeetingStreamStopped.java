package org.bigbluebutton.api.messaging.messages;

public class MeetingStreamStopped implements IMessage {
    public final String meetingId;

    public MeetingStreamStopped(String meetingId) {
        this.meetingId = meetingId;
    }
}
