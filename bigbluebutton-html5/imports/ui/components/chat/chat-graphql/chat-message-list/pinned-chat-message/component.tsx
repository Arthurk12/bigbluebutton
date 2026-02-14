import React, { useState, useMemo } from 'react';
import { defineMessages, useIntl } from 'react-intl';
import { Message } from '/imports/ui/Types/message';
import { setPinnedChatMessagesHidden, usePinnedChatMessagesHidden } from '/imports/ui/components/chat/chat-graphql/service';
import Styled from './styles';

const intlMessages = defineMessages({
  pinnedMessagesTitle: {
    id: 'app.chat.pinnedMessages.title',
    defaultMessage: 'Pinned messages',
  },
  pinnedByLabel: {
    id: 'app.chat.pinnedMessages.pinnedBy',
    defaultMessage: 'Pinned by',
  },
  toggleOpen: {
    id: 'app.chat.pinnedMessages.open',
    defaultMessage: 'Open pinned messages',
  },
  toggleCollapse: {
    id: 'app.chat.pinnedMessages.collapse',
    defaultMessage: 'Collapse pinned messages',
  },
  hidePinned: {
    id: 'app.chat.pinnedMessages.hidePinned',
    defaultMessage: 'Hide pinned messages',
  },
  showPinned: {
    id: 'app.chat.pinnedMessages.showPinned',
    defaultMessage: 'Show pinned messages',
  },
  tabsAria: {
    id: 'app.chat.pinnedMessages.tabsAria',
    defaultMessage: 'Pinned message tabs',
  },
  pinnedMessageTitle: {
    id: 'app.chat.pinnedMessages.messageTitle',
    defaultMessage: 'Pinned message {index}',
  },
});

interface PinnedMessageComponentProps {
  messages: Message[];
}

export default function PinnedMessageComponent({ messages }: PinnedMessageComponentProps) {
  const [collapsed, setCollapsed] = useState(false);
  const [activeIndex, setActiveIndex] = useState(0);

  const activeMessage = useMemo(() => messages[activeIndex] || null, [messages, activeIndex]);
  const intl = useIntl();
  const toggleAriaLabel = collapsed
    ? intl.formatMessage(intlMessages.toggleOpen)
    : intl.formatMessage(intlMessages.toggleCollapse);

  const pinnedHidden = usePinnedChatMessagesHidden();

  if (!messages || messages.length === 0) return null;

  const pinnedByName = activeMessage?.pinnedBy?.name || '';
  const formattedTime = activeMessage?.createdAt ? new Date(activeMessage.createdAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : '';
  const previewText = activeMessage?.message || (activeMessage?.messageAsHtml || '').replace(/<[^>]+>/g, '');

  return (
    <Styled.Wrapper role="region" aria-label={intl.formatMessage(intlMessages.pinnedMessagesTitle)}>
      <Styled.Header>
        <Styled.Title>
          <Styled.Icon iconName="pin_filled" />
          <Styled.PinnedBy>
            {intl.formatMessage(intlMessages.pinnedByLabel)}
            <Styled.PinnedByName>{pinnedByName}</Styled.PinnedByName>
          </Styled.PinnedBy>
        </Styled.Title>

        <Styled.Controls>
          <Styled.ToggleButton
            aria-pressed={pinnedHidden}
            aria-label={pinnedHidden
              ? intl.formatMessage(intlMessages.showPinned)
              : intl.formatMessage(intlMessages.hidePinned)}
            onClick={() => setPinnedChatMessagesHidden(true)}
          >
            <Styled.Icon iconName="visibility_off" />
          </Styled.ToggleButton>
          <Styled.ToggleButton
            aria-pressed={collapsed}
            aria-label={toggleAriaLabel}
            onClick={() => setCollapsed((c) => !c)}
          >
            {collapsed ? (
              <Styled.Icon iconName="arrow_forward_down" />
            ) : (
              <Styled.Icon iconName="arrow_forward_up" />
            )}
          </Styled.ToggleButton>
        </Styled.Controls>
      </Styled.Header>

      {collapsed ? (
        <>
          <Styled.MessagePreview aria-hidden>{previewText}</Styled.MessagePreview>
          {/* <Styled.Footer>
            <Styled.FooterLeft>
              {messages.length > 1 && (
                <Styled.Tabs role="tablist" aria-label={intl.formatMessage(intlMessages.tabsAria)}>
                  {messages.map((m, i) => (
                    <Styled.Tab
                      key={m.messageId}
                      active={i === activeIndex}
                      onClick={() => setActiveIndex(i)}
                      title={intl.formatMessage(intlMessages.pinnedMessageTitle, { index: i + 1 })}
                    />
                  ))}
                </Styled.Tabs>
              )}
            </Styled.FooterLeft>
          </Styled.Footer> */}
        </>
      ) : (
        <>
          <Styled.Divider />

          <Styled.Content>
            {activeMessage && (
              <Styled.MessageBox id={`pinned-message-${activeIndex}`} role="article">
                {/* eslint-disable-next-line react/no-danger -- message HTML is stored/trusted by server */}
                <div dangerouslySetInnerHTML={{ __html: activeMessage.messageAsHtml || '' }} />
              </Styled.MessageBox>
            )}
          </Styled.Content>

          <Styled.Footer>
            <Styled.FooterLeft>
              {messages.length > 1 && (
                <Styled.Tabs role="tablist" aria-label={intl.formatMessage(intlMessages.tabsAria)}>
                  {messages.map((m, i) => (
                    <Styled.Tab
                      key={m.messageId}
                      active={i === activeIndex}
                      onClick={() => setActiveIndex(i)}
                      title={intl.formatMessage(intlMessages.pinnedMessageTitle, { index: i + 1 })}
                    />
                  ))}
                </Styled.Tabs>
              )}
            </Styled.FooterLeft>

            <Styled.FooterRight>
              {activeMessage && (
                <div>
                  {activeMessage.senderName}
                  {' \u2022 '}
                  {formattedTime}
                </div>
              )}
            </Styled.FooterRight>
          </Styled.Footer>
        </>
      )}
    </Styled.Wrapper>
  );
}
