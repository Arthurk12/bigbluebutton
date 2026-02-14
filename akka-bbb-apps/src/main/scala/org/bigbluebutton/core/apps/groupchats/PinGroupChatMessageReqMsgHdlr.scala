package org.bigbluebutton.core.apps.groupchats

import org.bigbluebutton.common2.msgs._
import org.bigbluebutton.core.apps.PermissionCheck
import org.bigbluebutton.core.bus.MessageBus
import org.bigbluebutton.core.domain.MeetingState2x
import org.bigbluebutton.core.models.{ Roles, Users2x }
import org.bigbluebutton.core.running.{ HandlerHelpers, LiveMeeting }
import org.bigbluebutton.core2.MeetingStatus2x

trait PinGroupChatMessageReqMsgHdlr extends HandlerHelpers {
  this: GroupChatHdlrs =>

  def handle(msg: PinGroupChatMessageReqMsg, state: MeetingState2x, liveMeeting: LiveMeeting, bus: MessageBus): MeetingState2x = {
    val chatDisabled: Boolean = liveMeeting.props.meetingProp.disabledFeatures.contains("chat")
    var newState = state

    for {
      user <- Users2x.findWithIntId(liveMeeting.users2x, msg.header.userId)
      groupChat <- state.groupChats.find(msg.body.chatId)
    } yield {
      val userIsModerator = user.role == Roles.MODERATOR_ROLE

      // Only proceed when chat is enabled
      if (!chatDisabled) {
        for {
          gcMessage <- groupChat.msgs.find(gcm => gcm.id == msg.body.messageId)
        } yield {
          val messageIsPinned = groupChat.isPinned(gcMessage.id)

          if (!userIsModerator) {
            val reason = "User doesn't have permission to pin chat message"
            PermissionCheck.ejectUserForFailedPermission(msg.header.meetingId, msg.header.userId, reason, bus.outGW, liveMeeting)
          } else if (messageIsPinned) {
            // already pinned — nothing to do
          } else {
            val logger = org.slf4j.LoggerFactory.getLogger(this.getClass)
            logger.info(s"Pin requested by user=${msg.header.userId} for message=${gcMessage.id} chat=${msg.body.chatId} in meeting=${liveMeeting.props.meetingProp.intId}")

            // prefer meeting-level setting; fallback to system-config if not set or <= 0
            val configuredLimit: Int = {
              val meetingLimit = liveMeeting.props.meetingProp.maxPinnedChatMessages
              if (meetingLimit > 0) meetingLimit else maxPinnedChatMessages
            }

            val (updatedGroupChat, evictedOpt) = GroupChatApp.pinGroupChatMessage(liveMeeting.props.meetingProp.intId, groupChat, state.groupChats, gcMessage, user.intId, configuredLimit)

            // If an eviction happened, notify clients about the unpin first
            evictedOpt.foreach { evictedId =>
              val unpinEv = buildGroupChatMessageUnpinEvtMsg(liveMeeting.props.meetingProp.intId, msg.body.chatId, msg.header.userId, evictedId)
              bus.outGW.send(unpinEv)
              logger.info(s"Evicted pinned message=${evictedId} from chat=${msg.body.chatId}")
            }

            val event = buildGroupChatMessagePinEvtMsg(liveMeeting.props.meetingProp.intId, msg.body.chatId, msg.header.userId, gcMessage.id)
            bus.outGW.send(event)
            logger.info(s"Pin event sent for message=${gcMessage.id} chat=${msg.body.chatId}")
            newState = state.update(updatedGroupChat)
          }
        }
      }
    }

    newState
  }
}
