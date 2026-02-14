import React, {
  useMemo,
  useEffect,
} from 'react';
import useChat from '/imports/ui/core/hooks/useChat';
import logger from '/imports/startup/client/logger';
import { Message } from '/imports/ui/Types/message';
import useDeduplicatedSubscription from '/imports/ui/core/hooks/useDeduplicatedSubscription';
import { usePinnedChatMessagesHidden, setPinnedChatMessagesHidden } from '/imports/ui/components/chat/chat-graphql/service';
import {
  CHAT_MESSAGE_PUBLIC_SUBSCRIPTION,
  ChatMessageSubscriptionResponse,
} from './queries';
import { PinnedChatMessageProps } from './types';
import PinnedMessageComponent from './component';
import useStabilizedList from '/imports/ui/core/hooks/useStabilizedList';

export const PinnedChatMessageContainer: React.FC<PinnedChatMessageProps> = ({ openChatId }) => {
  const { data: chats } = useChat(
    (chat) => ({ chatId: chat.chatId, pinnedMessageIds: chat.pinnedMessageIds }),
    { chatId: openChatId, skip: !openChatId },
  );

  const chat = useMemo(() => (
    Array.isArray(chats) ? chats.find((c) => c.chatId === openChatId) : chats
  ), [chats, openChatId]);

  const CHAT_CONFIG = window.meetingClientSettings?.public?.chat ?? {};
  const PUBLIC_GROUP_CHAT_KEY = CHAT_CONFIG.public_group_id;

  const isPublicChat = openChatId && openChatId === PUBLIC_GROUP_CHAT_KEY;
  const pinnedMessagesIds = useMemo(() => chat?.pinnedMessageIds ?? [], [chat]);

  const {
    data: pinnedMessagesData,
    error: pinnedMessagesError,
  } = useDeduplicatedSubscription<ChatMessageSubscriptionResponse>(
    CHAT_MESSAGE_PUBLIC_SUBSCRIPTION,
    {
      variables: { messageIds: pinnedMessagesIds },
      skip: pinnedMessagesIds.length === 0,
    },
  );

  const pinnedMessages: Message[] = pinnedMessagesData?.chat_message_public || [];

  // prevents pinned messages "blink" effect when a new message is pinned or unpinned
  const displayedMessages = useStabilizedList<Message>(pinnedMessages, {
    getId: (m) => m.messageId,
    expectedIds: pinnedMessagesIds,
  });

  const pinnedMessagesHidden = usePinnedChatMessagesHidden();

  useEffect(() => {
    // the pinned messages header shortcut should vanish when there is no pinned message.
    if (!isPublicChat || !openChatId || displayedMessages.length === 0) {
      setPinnedChatMessagesHidden(false);
    }
  }, [isPublicChat, openChatId, displayedMessages]);

  if (pinnedMessagesError) {
    logger.error({
      logCode: 'pinned_messages_subscription_error',
      extraInfo: { error: pinnedMessagesError },
    }, `Error subscribing to pinned messages: ${pinnedMessagesError}`);
    return null;
  }
  if (pinnedMessagesHidden || !isPublicChat || !openChatId) return null;
  if (displayedMessages.length === 0) return null;

  return (
    <PinnedMessageComponent messages={displayedMessages} />
  );
};

export default PinnedChatMessageContainer;
