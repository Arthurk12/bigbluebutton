package org.bigbluebutton.api.messaging.messages;

public class UpdateTransferStatus implements IMessage {
    public final String meetingId;
    public final Boolean state;

    public UpdateTransferStatus(String meetingId, Boolean transfer) {
        this.meetingId = meetingId;
        this.state = transfer;
    }
}
