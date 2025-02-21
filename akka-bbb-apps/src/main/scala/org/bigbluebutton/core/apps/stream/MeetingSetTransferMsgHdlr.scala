package org.bigbluebutton.core.apps.stream

import org.bigbluebutton.common2.msgs._
import org.bigbluebutton.core2.MeetingStatus2x
import org.bigbluebutton.core.bus.MessageBus
import org.bigbluebutton.core.running.LiveMeeting

trait MeetingSetTransferMsgHdlr {
  this: StreamApp2x =>

  def handle(msg: MeetingSetTransferMsg, liveMeeting: LiveMeeting, bus: MessageBus): Unit = {
    log.debug("Received MeetingSetTransferMsg {}", MeetingSetTransferMsg)
    def broadcastEvent(transferState: Boolean): Unit = {
      val routing = Routing.addMsgToClientRouting(
        MessageTypes.BROADCAST_TO_MEETING,
        liveMeeting.props.meetingProp.intId,
        msg.header.userId
      )
      val envelope = BbbCoreEnvelope(MeetingSetTransferEvtMsg.NAME, routing)
      val header = BbbCoreHeaderWithMeetingId(MeetingSetTransferEvtMsg.NAME, liveMeeting.props.meetingProp.intId)
      val body = MeetingSetTransferEvtMsgBody(transferState)
      val event = MeetingSetTransferEvtMsg(header, body)
      val msgEvent = BbbCommonEnvCoreMsg(envelope, event)
      bus.outGW.send(msgEvent)
    }

    if (MeetingStatus2x.isTransfer(liveMeeting.status) != msg.body.state) {
      MeetingStatus2x.setTransfer(liveMeeting.status, msg.body.state)
      broadcastEvent(msg.body.state)
    } else {
      log.debug("Not setting transfer to same value");
    }

  }
}
