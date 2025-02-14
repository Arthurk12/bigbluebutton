package org.bigbluebutton.common2.msgs

// In messages
object MeetingStreamStartedMsg { val NAME = "MeetingStreamStartedMsg" }
case class MeetingStreamStartedMsg(header: BbbClientMsgHeader, body: MeetingStreamStartedMsgBody) extends StandardMsg
case class MeetingStreamStartedMsgBody(streamUrl: String, streamType: String, videoUrl: String, sharedSecret: String)

object MeetingStreamStoppedMsg { val NAME = "MeetingStreamStoppedMsg" }
case class MeetingStreamStoppedMsg(header: BbbClientMsgHeader, body: MeetingStreamStoppedMsgBody) extends StandardMsg
case class MeetingStreamStoppedMsgBody()

object UserConnectedToTransferSysMsg { val NAME = "UserConnectedToTransferSysMsg" }
case class UserConnectedToTransferSysMsg(header: BbbClientMsgHeader, body: UserConnectedToTransferSysMsgBody) extends StandardMsg
case class UserConnectedToTransferSysMsgBody(
    intUserId:    String,
    userName:     String,
    userdata:     java.util.Map[String, String],
    extMeetingId: String,
    extUserId:    String,
    sessionToken: String,
    intMeetingId: String,
    userSecret:   String
)

object UserDisconnectedFromTransferSysMsg { val NAME = "UserDisconnectedFromTransferSysMsg" }
case class UserDisconnectedFromTransferSysMsg(header: BbbClientMsgHeader, body: UserDisconnectedFromTransferSysMsgBody) extends StandardMsg
case class UserDisconnectedFromTransferSysMsgBody(
    intUserId:    String,
    userName:     String,
    userdata:     java.util.Map[String, String],
    extMeetingId: String,
    extUserId:    String,
    sessionToken: String,
    intMeetingId: String,
    userSecret:   String
)

object MeetingStreamSetShowCaptionsMsg { val NAME = "MeetingStreamSetShowCaptionsMsg" }
case class MeetingStreamSetShowCaptionsMsg(header: BbbClientMsgHeader, body: MeetingStreamSetShowCaptionsMsgBody) extends StandardMsg
case class MeetingStreamSetShowCaptionsMsgBody(showCaptions: Boolean)

// Out messages
object MeetingStreamStartedEvtMsg { val NAME = "MeetingStreamStartedEvtMsg" }
case class MeetingStreamStartedEvtMsg(header: BbbCoreHeaderWithMeetingId, body: MeetingStreamStartedEvtMsgBody) extends BbbCoreMsg
case class MeetingStreamStartedEvtMsgBody(streamUrl: String, streamType: String, videoUrl: String, sharedSecret: String)

object MeetingStreamStoppedEvtMsg { val NAME = "MeetingStreamStoppedEvtMsg" }
case class MeetingStreamStoppedEvtMsg(header: BbbCoreHeaderWithMeetingId, body: MeetingStreamStoppedEvtMsgBody) extends BbbCoreMsg
case class MeetingStreamStoppedEvtMsgBody()

object RedirectedUserToTransferSysMsg { val NAME = "RedirectedUserToTransferSysMsg" }
case class RedirectedUserToTransferSysMsg(header: BbbCoreHeaderWithMeetingId, body: RedirectedUserToTransferSysMsgBody) extends BbbCoreMsg
case class RedirectedUserToTransferSysMsgBody(
    intUserId:    String,
    userName:     String,
    userdata:     java.util.Map[String, String],
    extMeetingId: String,
    extUserId:    String,
    sessionToken: String
)

object UserConnectedToTransferEvtMsg { val NAME = "UserConnectedToTransferEvtMsg" }
case class UserConnectedToTransferEvtMsg(header: BbbCoreHeaderWithMeetingId, body: UserConnectedToTransferEvtMsgBody) extends BbbCoreMsg
case class UserConnectedToTransferEvtMsgBody(
    intUserId: String,
    userName:  String,
    userdata:  java.util.Map[String, String],
    extUserId: String
)

object UserDisconnectedFromTransferEvtMsg { val NAME = "UserDisconnectedFromTransferEvtMsg" }
case class UserDisconnectedFromTransferEvtMsg(header: BbbCoreHeaderWithMeetingId, body: UserDisconnectedFromTransferEvtMsgBody) extends BbbCoreMsg
case class UserDisconnectedFromTransferEvtMsgBody(
    intUserId: String,
    userName:  String,
    userdata:  java.util.Map[String, String],
    extUserId: String
)

object MeetingStreamSetShowCaptionsEvtMsg { val NAME = "MeetingStreamSetShowCaptionsEvtMsg" }
case class MeetingStreamSetShowCaptionsEvtMsg(header: BbbCoreHeaderWithMeetingId, body: MeetingStreamSetShowCaptionsEvtMsgBody) extends BbbCoreMsg
case class MeetingStreamSetShowCaptionsEvtMsgBody(showCaptions: Boolean)
