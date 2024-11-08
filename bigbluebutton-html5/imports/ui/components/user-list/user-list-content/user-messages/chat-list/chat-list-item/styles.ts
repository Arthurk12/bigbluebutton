import styled from 'styled-components';
import { fontSizeSmall } from '/imports/ui/stylesheets/styled-components/typography';
import {
  lgPaddingY,
  smPaddingY,
  borderSize,
  userIndicatorsOffset,
} from '/imports/ui/stylesheets/styled-components/general';
import {
  colorGrayDark,
  colorOffWhite,
  listItemBgHover,
  colorGrayLight,
  colorWhite,
  userListBg,
  colorSuccess,
  itemFocusBorder,
  unreadMessagesBg,
  colorGrayLightest,
} from '/imports/ui/stylesheets/styled-components/palette';

interface UserAvatarProps {
  color: string;
  moderator: boolean;
  avatar: string;
  emoji?: string;
}

interface ChatNameMainProps {
  active: boolean;
}

interface ChatListItemProps {
  active: boolean;
  ref: React.Ref<HTMLElement | undefined>;
}

const ChatListItemLink = styled.div`
  display: flex;
  flex-grow: 1;
  align-items: center;
  text-decoration: none;
  width: 100%;
`;

const ChatIcon = styled.div`
  flex: 0 0 2.2rem;
`;

const ChatName = styled.div`
  display: flex;
  align-items: center;
  flex-grow: 1;
  justify-content: center;
  width: 50%;
  padding-right: ${smPaddingY};
`;

const ChatNameMain = styled.span`
  margin: 0;
  min-width: 0;
  display: inline-block;
  white-space: nowrap;
  overflow: hidden;
  font-weight: 400;
  font-size: ${fontSizeSmall};
  color: ${colorGrayDark};
  flex-grow: 1;
  line-height: 2;
  text-align: left;
  padding: 0 0 0 ${lgPaddingY};
  text-overflow: ellipsis;

  [dir="rtl"] & {
    text-align: right;
    padding: 0 ${lgPaddingY} 0 0;
  }

  ${({ active }: ChatNameMainProps) => active && `
    background-color: ${listItemBgHover};
  `}
`;

const ChatListItem = styled.button<ChatListItemProps>`
  display: flex;
  flex-flow: row;
  border-top-left-radius: 5px;
  border-bottom-left-radius: 5px;
  border-top-right-radius: 0;
  border-bottom-right-radius: 0;
  cursor: pointer;
  border-color: transparent;
  border-width: 0;

  [dir="rtl"] & {
    border-top-left-radius: 0;
    border-bottom-left-radius: 0;
    border-top-right-radius: 5px;
    border-bottom-right-radius: 5px;
  }

  &:first-child {
    margin-top: 0;
  }

  &:hover {
    outline: transparent;
    outline-style: dotted;
    outline-width: ${borderSize};
    background-color: ${listItemBgHover};
  }

  &:focus {
    outline: transparent;
    outline-width: ${borderSize};
    outline-style: solid;
    background-color: ${listItemBgHover};
    box-shadow: inset 0 0 0 ${borderSize} ${itemFocusBorder}, inset 1px 0 0 1px ${itemFocusBorder};
  }
  cursor: pointer;
  text-decoration: none;
  flex-grow: 1;
  line-height: 2;
  color: ${colorGrayDark};
  background-color: ${colorOffWhite};
  padding-top: ${lgPaddingY};
  padding-bottom: ${lgPaddingY};
  padding-left: ${lgPaddingY};
  padding-right: 0;
  margin-left: ${borderSize};
  margin-top: ${borderSize};
  margin-bottom: ${borderSize};
  margin-right: 0;

  [dir="rtl"] & {
    padding-left: 0;
    padding-right: ${lgPaddingY};
    margin-left: 0;
    margin-right: ${borderSize};
  }
  ${({ active }: ChatListItemProps) => active && `
    outline: transparent;
    outline-style: dotted;
    outline-width: ${borderSize};
    background-color: ${colorGrayLightest};
  `}
`;

const ChatThumbnail = styled.div`
  display: flex;
  flex-flow: column;
  color: ${colorGrayLight};
  justify-content: center;
  font-size: 175%;
`;

const UnreadMessages = styled.div`
  display: flex;
  flex-flow: column;
  justify-content: center;
  margin-left: auto;
  [dir="rtl"] & {
    margin-right: auto;
    margin-left: 0;
  }
`;
const UnreadMessagesText = styled.div`
  display: flex;
  flex-flow: column;
  margin: 0;
  justify-content: center;
  color: ${colorWhite};
  line-height: calc(1rem + 1px);
  padding: 0 0.5rem;
  text-align: center;
  border-radius: 0.5rem/50%;
  font-size: 0.8rem;
  background-color: ${unreadMessagesBg};
`;

export default {
  ChatListItemLink,
  ChatIcon,
  ChatName,
  ChatNameMain,
  ChatListItem,
  ChatThumbnail,
  UnreadMessages,
  UnreadMessagesText,
};
