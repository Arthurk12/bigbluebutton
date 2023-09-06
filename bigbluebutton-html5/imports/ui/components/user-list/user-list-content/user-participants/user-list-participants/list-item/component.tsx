import React from 'react';
import browserInfo from '/imports/utils/browserInfo';
import { defineMessages, useIntl } from 'react-intl';
import Icon from '/imports/ui/components/common/icon/component';
import { User } from '/imports/ui/Types/user';
import TooltipContainer from '/imports/ui/components/common/tooltip/container';
import Auth from '/imports/ui/services/auth';
import { LockSettings } from '/imports/ui/Types/meeting';
// Lodash is loaded
// eslint-disable-next-line import/no-extraneous-dependencies
import _ from 'lodash';
import Styled from './styles';

const messages = defineMessages({
  moderator: {
    id: 'app.userList.moderator',
    description: 'Text for identifying moderator user',
  },
  mobile: {
    id: 'app.userList.mobile',
    description: 'Text for identifying mobile user',
  },
  guest: {
    id: 'app.userList.guest',
    description: 'Text for identifying guest user',
  },
  sharingWebcam: {
    id: 'app.userList.sharingWebcam',
    description: 'Text for identifying who is sharing webcam',
  },
  locked: {
    id: 'app.userList.locked',
    description: 'Text for identifying locked user',
  },
  breakoutRoom: {
    id: 'app.createBreakoutRoom.room',
    description: 'breakout room',
  },
  you: {
    id: 'app.userList.you',
    description: 'Text for identifying your user',
  },
});

// @ts-ignore - temporary, while meteor exists in the project
const ROLE_MODERATOR = Meteor.settings.public.user.role_moderator;
// @ts-ignore - temporary, while meteor exists in the project
const LABEL = Meteor.settings.public.user.label;

const { isChrome, isFirefox, isEdge } = browserInfo;

interface UserListItemProps {
  user: User;
  lockSettings: LockSettings;
}

const UserListItem: React.FC<UserListItemProps> = ({ user, lockSettings }) => {
  const intl = useIntl();
  const voiceUser = user.voice;
  const subs = [
    (user.role === ROLE_MODERATOR && LABEL.moderator) && intl.formatMessage(messages.moderator),
    (user.guest && LABEL.guest) && intl.formatMessage(messages.guest),
    (user.mobile && LABEL.mobile) && intl.formatMessage(messages.mobile),
    (user.locked && lockSettings.hasActiveLockSetting && !user.isModerator)
    && (
      <span key={_.uniqueId('lock-')}>
        <Icon iconName="lock" className={undefined} prependIconName={undefined} rotate={undefined} />
        &nbsp;
        {intl.formatMessage(messages.locked)}
      </span>
    ),
    user.lastBreakoutRoom?.currentlyInRoom && (
      <span key={_.uniqueId('breakout-')}>
        <Icon iconName="rooms" className={undefined} prependIconName={undefined} rotate={undefined} />
        &nbsp;
        {user.lastBreakoutRoom?.shortName
          ? intl.formatMessage(messages.breakoutRoom, { 0: user.lastBreakoutRoom?.sequence })
          : user.lastBreakoutRoom?.shortName}
      </span>
    ),
    (user.cameras.length > 0 && LABEL.sharingWebcam) && (
      <span key={_.uniqueId('breakout-')}>
        {user.pinned === true
          ? <Icon iconName="pin-video_on" className={undefined} prependIconName={undefined} rotate={undefined} />
          : <Icon iconName="video" className={undefined} prependIconName={undefined} rotate={undefined} />}
        &nbsp;
        {intl.formatMessage(messages.sharingWebcam)}
      </span>
    ),
  ].filter(Boolean);

  type EmojiStatus = 'away' | 'raiseHand' | 'neutral' | 'confused' | 'sad' | 'happy' | 'applause' | 'thumbsUp' | 'thumbsDown' | 'none';

  const EMOJI_STATUSES: Record<EmojiStatus, string> = {
    away: 'time',
    raiseHand: 'hand',
    neutral: 'undecided',
    confused: 'confused',
    sad: 'sad',
    happy: 'happy',
    applause: 'applause',
    thumbsUp: 'thumbs_up',
    thumbsDown: 'thumbs_down',
    none: 'none',
  } as const;
  const emojiKey = user.emoji;
  const emojiIcon = emojiKey !== 'none' ? EMOJI_STATUSES[emojiKey as EmojiStatus] : user.name.toLowerCase().slice(0, 2);

  const iconUser = (
    <Icon
      iconName={emojiIcon}
      className={undefined}
      prependIconName={undefined}
      rotate={undefined}
    />
  );

  const avatarContent = user.lastBreakoutRoom?.currentlyInRoom ? user.lastBreakoutRoom?.sequence : iconUser

  return (
    <Styled.UserItemContents>
      <Styled.Avatar
        moderator={user.role === ROLE_MODERATOR}
        presenter={user.presenter || false}
        talking={voiceUser?.talking || false}
        muted={voiceUser?.muted || false}
        listenOnly={voiceUser?.listenOnly || false}
        voice={voiceUser?.joined || false}
        noVoice={!(voiceUser?.joined) || false}
        color={user.color}
        whiteboardAccess={user?.presPagesWritable?.length > 0}
        animations
        emoji={user.emoji !== 'none'}
        avatar={user.avatar || ''}
        isChrome={isChrome}
        isFirefox={isFirefox}
        isEdge={isEdge}
      >
        {avatarContent}
      </Styled.Avatar>
      <Styled.UserNameContainer>
        <Styled.UserName>
          <TooltipContainer title={user.name}>
            <span>{user.name}</span>
          </TooltipContainer>
          &nbsp;
          {(user.userId === Auth.userID) ? `(${intl.formatMessage(messages.you)})` : ''}
        </Styled.UserName>
        <Styled.UserNameSub>
          {subs.length ? subs.reduce((prev, curr) => [prev, ' | ', curr]) : null}
        </Styled.UserNameSub>
      </Styled.UserNameContainer>
    </Styled.UserItemContents>
  );
};

export default UserListItem;