import React, { useMemo } from 'react';
import { TransitionGroup, CSSTransition } from 'react-transition-group';
import Styled from './styles';
import PrivateChatListItem from './chat-list-item/component';
import useChat from '/imports/ui/core/hooks/useChat';
import { Chat } from '/imports/ui/Types/chat';
import { GraphqlDataHookSubscriptionResponse } from '/imports/ui/Types/hook';
import roveBuilder from '/imports/ui/core/utils/keyboardRove';

interface ChatListProps {
  chats: Chat[],
}

const getActiveChats = (chats: Chat[], chatNodeRef: React.Ref<HTMLButtonElement>) => chats.map((chat, idx) => (
  <CSSTransition
    classNames="transition"
    appear
    enter
    exit={false}
    timeout={0}
    key={chat.chatId}
    nodeRef={chatNodeRef}
  >
    <Styled.ListTransition>
      <PrivateChatListItem
        chat={chat}
        chatNodeRef={chatNodeRef}
        index={idx}
      />
    </Styled.ListTransition>
  </CSSTransition>
));

const PrivateChatList: React.FC<ChatListProps> = ({ chats }) => {
  const messageListRef = React.useRef<HTMLDivElement | null>(null);
  const messageItemsRef = React.useRef<HTMLDivElement | null>(null);
  const chatNodeRef = React.useRef<HTMLButtonElement | null>(null);

  const rove = useMemo(() => roveBuilder(messageItemsRef, 'chat-list'), []);

  return (
    <Styled.ScrollableList
      role="tabpanel"
      tabIndex={0}
      ref={messageListRef}
      onKeyDown={(e:React.KeyboardEvent<HTMLDivElement>) => rove(e)}
    >
      <TransitionGroup>
        {getActiveChats(chats, chatNodeRef)}
      </TransitionGroup>
    </Styled.ScrollableList>
  );
};

const PrivateChatListContainer: React.FC = () => {
  const { data } = useChat((chat) => chat) as GraphqlDataHookSubscriptionResponse<Chat[]>;
  const chats = (data || []).filter((chat) => !chat.public && chat.totalMessages !== 0);

  return (
    <PrivateChatList chats={chats} />
  );
};

export default PrivateChatListContainer;
