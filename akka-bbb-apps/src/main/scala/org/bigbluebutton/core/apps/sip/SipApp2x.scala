package org.bigbluebutton.core.apps.sip

import org.apache.pekko.actor.ActorContext
import org.apache.pekko.event.Logging

class SipApp2x(implicit val context: ActorContext)
  extends SipEndpointCamStartMsgHdlr
  with SipEndpointCamStopMsgHdlr {

  val log = Logging(context.system, getClass)
}
