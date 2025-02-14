package org.bigbluebutton.core.apps.stream

import org.bigbluebutton.common2.msgs._
import org.bigbluebutton.core.apps.StreamModel
import org.bigbluebutton.core.bus.MessageBus
import org.bigbluebutton.core.running.LiveMeeting

trait MeetingStreamStartedMsgHdlr {
  this: StreamApp2x =>

  def handle(msg: MeetingStreamStartedMsg, liveMeeting: LiveMeeting, bus: MessageBus): Unit = {
    log.debug("Received MeetingStreamStartedMsg {}", MeetingStreamStartedMsg)
    def broadcastEvent(streamUrl: String, streamType: String, videoUrl: String, sharedSecret: String): Unit = {
      val routing = collection.immutable.HashMap("sender" -> "bbb-apps-akka")
      val envelope = BbbCoreEnvelope(MeetingStreamStartedEvtMsg.NAME, routing)
      val header = BbbCoreHeaderWithMeetingId(MeetingStreamStartedEvtMsg.NAME, liveMeeting.props.meetingProp.intId)
      val body = MeetingStreamStartedEvtMsgBody(streamUrl, streamType, videoUrl, sharedSecret)
      val event = MeetingStreamStartedEvtMsg(header, body)
      val msgEvent = BbbCommonEnvCoreMsg(envelope, event)
      bus.outGW.send(msgEvent)
    }

    if (StreamModel.getState(liveMeeting.streamModel)) {
      log.warning("Meeting already has a stream " + liveMeeting.props.meetingProp.intId)
    }

    StreamModel.setStream(liveMeeting.streamModel, true, msg.body.streamUrl, msg.body.streamType, msg.body.videoUrl, msg.body.sharedSecret);
    broadcastEvent(msg.body.streamUrl, msg.body.streamType, msg.body.videoUrl, msg.body.sharedSecret)
  }
}
