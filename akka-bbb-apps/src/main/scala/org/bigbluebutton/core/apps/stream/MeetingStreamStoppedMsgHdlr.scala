package org.bigbluebutton.core.apps.stream

import org.bigbluebutton.common2.msgs._
import org.bigbluebutton.core.apps.StreamModel
import org.bigbluebutton.core.bus.MessageBus
import org.bigbluebutton.core.running.LiveMeeting

trait MeetingStreamStoppedMsgHdlr {
  this: StreamApp2x =>

  def handle(msg: MeetingStreamStoppedMsg, liveMeeting: LiveMeeting, bus: MessageBus): Unit = {
    log.debug("Received MeetingStreamStoppedMsg {}", MeetingStreamStoppedMsg)
    def broadcastEvent(): Unit = {
      val routing = collection.immutable.HashMap("sender" -> "bbb-apps-akka")
      val envelope = BbbCoreEnvelope(MeetingStreamStoppedEvtMsg.NAME, routing)
      val header = BbbCoreHeaderWithMeetingId(MeetingStreamStoppedEvtMsg.NAME, liveMeeting.props.meetingProp.intId)
      val body = MeetingStreamStoppedEvtMsgBody()
      val event = MeetingStreamStoppedEvtMsg(header, body)
      val msgEvent = BbbCommonEnvCoreMsg(envelope, event)
      bus.outGW.send(msgEvent)
    }

    if (!StreamModel.getState(liveMeeting.streamModel)) {
      log.warning("Meeting stream already stopped " + liveMeeting.props.meetingProp.intId)
    }

    StreamModel.setStream(liveMeeting.streamModel, false);
    broadcastEvent()
  }
}
