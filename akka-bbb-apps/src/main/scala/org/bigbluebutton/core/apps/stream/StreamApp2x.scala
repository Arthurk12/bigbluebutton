package org.bigbluebutton.core.apps.stream

import org.apache.pekko.actor.ActorContext
import org.apache.pekko.event.Logging

class StreamApp2x(implicit val context: ActorContext)
  extends MeetingStreamStartedMsgHdlr
  with MeetingStreamStoppedMsgHdlr
  with UserConnectedToTransferMsgHdlr
  with UserDisconnectedFromTransferMsgHdlr
  with MeetingSetTransferMsgHdlr {

  val log = Logging(context.system, getClass)
}
