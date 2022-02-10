package org.bigbluebutton.core.apps.sip

import org.bigbluebutton.common2.msgs._
import org.bigbluebutton.core.bus.MessageBus
import org.bigbluebutton.core.running.LiveMeeting
import org.bigbluebutton.core.models.{ WebcamStream, Webcams }
import org.bigbluebutton.core.models.Users2x

trait SipEndpointCamStartMsgHdlr {
  this: SipApp2x =>

  def handle(msg: SipEndpointCamStartMsg, liveMeeting: LiveMeeting, bus: MessageBus): Unit = {
    // Keep this here instead of MsgBuilder to reduce conflicts
    def broadcastEvent(msg: SipEndpointCamStartMsg): Unit = {
      val routing = Routing.addMsgToClientRouting(
        MessageTypes.BROADCAST_TO_MEETING,
        liveMeeting.props.meetingProp.intId,
        msg.header.userId
      )
      val envelope = BbbCoreEnvelope(UserBroadcastCamStartedEvtMsg.NAME, routing)
      val header = BbbClientMsgHeader(
        UserBroadcastCamStartedEvtMsg.NAME,
        liveMeeting.props.meetingProp.intId,
        msg.header.userId
      )
      val body = UserBroadcastCamStartedEvtMsgBody(msg.header.userId, msg.body.streamId)
      val event = UserBroadcastCamStartedEvtMsg(header, body)
      val msgEvent = BbbCommonEnvCoreMsg(envelope, event)

      bus.outGW.send(msgEvent)
    }

    for {
      user <- Users2x.findWithIntId(liveMeeting.users2x, msg.header.userId)
    } yield {
      val webcamStream = new WebcamStream(
        msg.body.streamId,
        msg.header.userId,
        Set.empty
      )

      for {
        uvo <- Webcams.addWebcamStream(liveMeeting.webcams, webcamStream)
      } yield {
        broadcastEvent(msg)
      }
    }
  }
}
