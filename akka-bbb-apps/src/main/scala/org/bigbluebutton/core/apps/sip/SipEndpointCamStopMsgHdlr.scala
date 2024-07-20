package org.bigbluebutton.core.apps.sip

import org.bigbluebutton.common2.msgs._
import org.bigbluebutton.core.running.LiveMeeting
import org.bigbluebutton.core.bus.MessageBus
import org.bigbluebutton.core.models.Webcams
import org.bigbluebutton.core.apps.webcam.CameraHdlrHelpers

trait SipEndpointCamStopMsgHdlr {
  this: SipApp2x =>

  def handle(msg: SipEndpointCamStopMsg, liveMeeting: LiveMeeting, bus: MessageBus): Unit = {
    val meetingId: String = liveMeeting.props.meetingProp.intId
    val userId: String = msg.header.userId
    val streamId: String = msg.body.streamId

    for {
      publisherStream <- Webcams.findWithStreamId(liveMeeting.webcams, streamId)
    } yield {
      if (publisherStream.userId != userId) {
        log.error(
          "SIP endpoint does not camera stream: meetingId={}, userId={}, streamId={}",
          meetingId, userId, streamId
        )
      } else {
        for {
          _ <- Webcams.removeWebcamStream(liveMeeting.webcams, streamId)
        } yield {
          CameraHdlrHelpers.stopBroadcastedCam(
            liveMeeting,
            meetingId,
            userId,
            streamId,
            bus.outGW
          )
        }
      }
    }
  }
}
