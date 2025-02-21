package org.bigbluebutton.api.messaging.messages;

public class MeetingStreamStarted implements IMessage {
    public final String meetingId;
    public final String streamUrl;
    public final String streamType;
    public final String videoUrl;
    public final String sharedSecret;

    public MeetingStreamStarted(String meetingId, String streamUrl, String streamType, String videoUrl, String sharedSecret) {
        this.meetingId = meetingId;
        this.streamUrl = streamUrl;
        this.streamType = streamType;
        this.videoUrl = videoUrl;
        this.sharedSecret = sharedSecret;
    }
}
