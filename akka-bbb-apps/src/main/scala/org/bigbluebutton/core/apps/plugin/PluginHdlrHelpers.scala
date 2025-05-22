package org.bigbluebutton.core.apps.plugin

import org.bigbluebutton.common2.msgs.PluginDataChannelReplaceOrDeleteBaseBody
import org.bigbluebutton.core.db.PluginDataChannelEntryDAO
import org.bigbluebutton.core.models.{ DataChannel, PluginModel, Roles, UserState, Users2x }
import org.bigbluebutton.core.running.LiveMeeting
import org.bigbluebutton.core.models.RegisteredUsers

object PluginHdlrHelpers {
  def checkPermission(role: String, isPresenter: Boolean, permissionType: List[String], creatorCheck: => Boolean = false): List[Boolean] = {
    permissionType.map(_.toLowerCase).map {
      case "all"       => true
      case "moderator" => role == Roles.MODERATOR_ROLE
      case "presenter" => isPresenter
      case "creator"   => creatorCheck
      case _           => false
    }
  }
  def defaultCreatorCheck[T <: PluginDataChannelReplaceOrDeleteBaseBody](meetingId: String, msgBody: T, userId: String): Boolean = {
    val creatorUserId = PluginDataChannelEntryDAO.getEntryCreator(
      meetingId,
      msgBody.pluginName,
      msgBody.channelName,
      msgBody.subChannelName,
      msgBody.entryId
    )
    creatorUserId == userId
  }

  def dataChannelCheckingLogic(liveMeeting: LiveMeeting, userId: String,
                               pluginName: String, channelName: String,
                               caseSomeDataChannelAndPlugin: (String, Boolean, DataChannel, String) => Unit): Option[Unit] = {
    val pluginsDisabled: Boolean = liveMeeting.props.meetingProp.disabledFeatures.contains("plugins")
    val meetingId = liveMeeting.props.meetingProp.intId

    if (pluginsDisabled) {
      None
    } else {
      val userRoleAndPresenterOpt: Option[(String, Boolean)] = Users2x.findWithIntId(liveMeeting.users2x, userId) match {
        case Some(user) => Some((user.role, user.presenter))
        case None =>
          RegisteredUsers.findWithUserId(userId, liveMeeting.registeredUsers) match {
            case Some(_) => Some((Roles.AUTHENTICATED_ROLE, false))
            case None    => None
          }
      }

      userRoleAndPresenterOpt match {
        case Some((role, isPresenter)) =>
          PluginModel.getPluginByName(liveMeeting.plugins, pluginName) match {
            case Some(p) =>
              p.manifest.content.dataChannels.getOrElse(List()).find(dc => dc.name == channelName) match {
                case Some(dc) =>
                  caseSomeDataChannelAndPlugin(role, isPresenter, dc, meetingId)
                  Some(())
                case None =>
                  println(s"Data channel '${channelName}' not found in plugin '${pluginName}'.")
                  None
              }
            case None =>
              println(s"Plugin '${pluginName}' not found.")
              None
          }
        case None =>
          println(s"User with ID '$userId' not found in Users2x or RegisteredUsers.")
          None
      }
    }
  }
}
