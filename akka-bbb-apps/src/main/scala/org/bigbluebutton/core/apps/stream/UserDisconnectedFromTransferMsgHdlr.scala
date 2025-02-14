package org.bigbluebutton.core.apps.stream

import org.bigbluebutton.common2.msgs._
import org.bigbluebutton.core.apps.StreamModel
import org.bigbluebutton.core.bus.MessageBus
import org.bigbluebutton.core.running.LiveMeeting

trait UserDisconnectedFromTransferMsgHdlr {
  this: StreamApp2x =>

  def handle(msg: UserDisconnectedFromTransferSysMsg, liveMeeting: LiveMeeting, bus: MessageBus): Unit = {
    log.debug("Received UserDisconnectedFromTransferSysMsg {}", UserDisconnectedFromTransferSysMsg)
    def broadcastEvent(): Unit = {
      val routing = collection.immutable.HashMap("sender" -> "bbb-apps-akka")
      val envelope = BbbCoreEnvelope(UserDisconnectedFromTransferEvtMsg.NAME, routing)
      val header = BbbCoreHeaderWithMeetingId(UserDisconnectedFromTransferEvtMsg.NAME, liveMeeting.props.meetingProp.intId)
      val body = UserDisconnectedFromTransferEvtMsgBody(msg.body.intUserId, msg.body.userName, msg.body.userdata, msg.body.extUserId)
      val event = UserDisconnectedFromTransferEvtMsg(header, body)
      val msgEvent = BbbCommonEnvCoreMsg(envelope, event)
      bus.outGW.send(msgEvent)
    }

    broadcastEvent()
  }
}
