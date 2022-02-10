package org.bigbluebutton.common2.msgs

object SipEndpointCamStartMsg { val NAME = "SipEndpointCamStartMsg" }
case class SipEndpointCamStartMsg(header: BbbClientMsgHeader, body: SipEndpointCamStartMsgBody) extends StandardMsg
case class SipEndpointCamStartMsgBody(streamId: String)

object SipEndpointCamStopMsg { val NAME = "SipEndpointCamStopMsg" }
case class SipEndpointCamStopMsg(header: BbbClientMsgHeader, body: SipEndpointCamStopMsgBody) extends StandardMsg
case class SipEndpointCamStopMsgBody(streamId: String)
