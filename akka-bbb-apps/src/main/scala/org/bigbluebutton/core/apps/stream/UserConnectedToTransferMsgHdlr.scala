package org.bigbluebutton.core.apps.stream

import org.bigbluebutton.common2.msgs._
import org.bigbluebutton.core.apps.StreamModel
import org.bigbluebutton.core.bus.MessageBus
import org.bigbluebutton.core.running.LiveMeeting

trait UserConnectedToTransferMsgHdlr {
  this: StreamApp2x =>

  def handle(msg: UserConnectedToTransferSysMsg, liveMeeting: LiveMeeting, bus: MessageBus): Unit = {
    log.debug("Received UserConnectedToTransferSysMsg {}", UserConnectedToTransferSysMsg)
    def broadcastEvent(): Unit = {
      val routing = collection.immutable.HashMap("sender" -> "bbb-apps-akka")
      val envelope = BbbCoreEnvelope(UserConnectedToTransferEvtMsg.NAME, routing)
      val header = BbbCoreHeaderWithMeetingId(UserConnectedToTransferEvtMsg.NAME, liveMeeting.props.meetingProp.intId)
      val body = UserConnectedToTransferEvtMsgBody(msg.body.intUserId, msg.body.userName, msg.body.userdata, msg.body.extUserId)
      val event = UserConnectedToTransferEvtMsg(header, body)
      val msgEvent = BbbCommonEnvCoreMsg(envelope, event)
      bus.outGW.send(msgEvent)
    }

    broadcastEvent()
  }
}
