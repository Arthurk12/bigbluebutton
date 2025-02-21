package org.bigbluebutton.core.apps.stream

import org.bigbluebutton.common2.msgs._
import org.bigbluebutton.core.apps.StreamModel
import org.bigbluebutton.core.bus.MessageBus
import org.bigbluebutton.core.running.LiveMeeting

trait MeetingStreamSetShowCaptionsMsgHdlr {
  this: StreamApp2x =>

  def handle(msg: MeetingStreamSetShowCaptionsMsg, liveMeeting: LiveMeeting, bus: MessageBus): Unit = {
    log.debug("Received MeetingStreamSetShowCaptionsEvtMsg {}", MeetingStreamSetShowCaptionsMsg)
    def broadcastEvent(showCaptions: Boolean): Unit = {
      val routing = collection.immutable.HashMap("sender" -> "bbb-apps-akka")
      val envelope = BbbCoreEnvelope(MeetingStreamSetShowCaptionsEvtMsg.NAME, routing)
      val header = BbbCoreHeaderWithMeetingId(MeetingStreamSetShowCaptionsEvtMsg.NAME, liveMeeting.props.meetingProp.intId)
      val body = MeetingStreamSetShowCaptionsEvtMsgBody(showCaptions)
      val event = MeetingStreamSetShowCaptionsEvtMsg(header, body)
      val msgEvent = BbbCommonEnvCoreMsg(envelope, event)

      bus.outGW.send(msgEvent)
    }

    StreamModel.setShowCaptions(liveMeeting.streamModel, msg.body.showCaptions);

    log.debug("setShowCaptions {}", msg.body.showCaptions);
    broadcastEvent(msg.body.showCaptions);
  }
}

