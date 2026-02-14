import styled from 'styled-components';
import {
  colorWhite,
  colorPrimary,
  colorBlueAux,
  appsGalleryOutlineColor,
  appsPanelTextColor,
  colorNeutral2,
} from '/imports/ui/stylesheets/styled-components/palette';
import OrIcon from '/imports/ui/components/common/icon/component';

const Wrapper = styled.div`
  background: ${colorWhite};
  border-radius: 6px;
  border: 1px solid ${appsGalleryOutlineColor};
  padding: 1rem;
  width: 100%;
  display: flex;
  flex-direction: column;
  gap: 8px;
`;

const Header = styled.div`
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
`;

const Title = styled.div`
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 1.2rem;
`;

const Divider = styled.hr`
  height: 1px;
  background-color: ${colorBlueAux};
  border: none;
  margin: 0px;
`;

const PinnedBy = styled.span`
  color: inherit;
  font-size: 13px;
`;

const PinnedByName = styled.span`
  color: ${colorPrimary};
  font-weight: 600;
  margin-left: 6px;
`;

const Controls = styled.div`
  display: flex;
  gap: 6px;
  align-items: center;
`;

const ToggleButton = styled.button`
  background: transparent;
  border: none;
  cursor: pointer;
  padding: 4px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
`;

const Tabs = styled.div`
  display: flex;
  gap: 6px;
  align-items: center;
`;

const Tab = styled.button<{ active?: boolean }>`
  width: 8px;
  height: 8px;
  border-radius: 50%;
  border: none;
  background: ${(p) => (p.active ? `${colorPrimary}` : `${appsGalleryOutlineColor}`)};
  cursor: pointer;
  padding: 0;
`;

const Content = styled.div`
  display: block;
`;

const MessagePreview = styled.div`
  color: inherit;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  /* prevent long continuous text/URLs from overflowing the preview */
  overflow-wrap: anywhere;
  word-break: break-word;
`;

const MessageBox = styled.div`
  border-radius: 4px;
  color: ${appsPanelTextColor};
  line-height: 1.4;

  /* allow wrapping of long words/URLs and preserve line breaks */
  overflow-wrap: anywhere;
  word-break: break-word;
  hyphens: auto;

  /* Remove large default margins coming from user-generated HTML (e.g. <p>)
     and keep small, consistent spacing. This prevents paragraphs from
     creating excessive vertical gaps inside the pinned message card. */
  p,
  h1, h2, h3, h4, h5, h6,
  blockquote {
    margin: 0; /* reset heavy browser defaults */
    padding: 0;
  }

  /* small, controlled spacing between consecutive paragraphs */
  p + p {
    margin-top: 0.5rem;
  }

  /* lists: reset outer margins but keep indentation for readability */
  ul, ol {
    margin: 0.25rem 0;
    padding-left: 1.25rem;
  }

  /* anchors and inline elements should also wrap */
  a {
    overflow-wrap: anywhere;
    word-break: break-word;
    hyphens: auto;
  }

  /* images must not overflow */
  img {
    max-width: 100%;
    height: auto;
    display: block;
  }

  /* code/pre: prefer wrapping; allow scroll if extremely long */
  pre,
  code {
    white-space: pre-wrap;
    word-break: break-word;
    overflow-wrap: anywhere;
    max-width: 100%;
  }
`;

const Footer = styled.div`
  display: flex;
  align-items: center;
  justify-content: space-between;
`;

const FooterLeft = styled.div`
  display: flex;
  align-items: center;
  gap: 8px;
`;

const FooterRight = styled.div`
  color: ${colorNeutral2};
  font-size: 14px;
`;

const Icon = styled(OrIcon)<{ iconName: string }>`
  color: ${colorNeutral2};
`;

export default {
  Wrapper,
  Header,
  Title,
  Divider,
  PinnedBy,
  PinnedByName,
  Controls,
  ToggleButton,
  Tabs,
  Tab,
  Content,
  MessagePreview,
  MessageBox,
  Footer,
  FooterLeft,
  FooterRight,
  Icon,
};
