import styled from 'styled-components';
import Button from '/imports/ui/components/common/button/component';
import {
  smPaddingX,
  lgPaddingY,
  jumboPaddingY,
} from '/imports/ui/stylesheets/styled-components/general';
import { colorGray } from '/imports/ui/stylesheets/styled-components/palette';
import { lineHeightBase } from '/imports/ui/stylesheets/styled-components/typography';

const Container = styled.div`
  display: flex;
  align-items: flex-start;
  flex-direction: column;
  padding: 0;
  margin-top: 0;
  margin: auto;
`;

const Description = styled.div`
  text-align: left;
  line-height: ${lineHeightBase};
  color: ${colorGray};
  margin-bottom: ${jumboPaddingY};
`;

const DescriptionText = styled.span`
  white-space: pre-line;
`;

const Checkbox = styled.input`
  position: relative;
  top: 0.134rem;
  margin-right: 0.5rem;

  [dir="rtl"] & {
    margin-right: 0;
    margin-left: 0.5rem;
  }
`;

const Footer = styled.div`
  display:flex;
  margin-bottom: ${lgPaddingY};
`;

const ConfirmationButton = styled(Button)`
  padding-right: ${jumboPaddingY};
  padding-left: ${jumboPaddingY};
  margin: 0;
`;

const CancelButton = styled(ConfirmationButton)`
  margin: 0 ${smPaddingX} 0 0;

  [dir="rtl"] & {
    margin: 0 0 0 ${smPaddingX};
  }
`;

const Label = styled.label`
  display: block;
`;

export default {
  Container,
  Description,
  DescriptionText,
  Checkbox,
  Footer,
  ConfirmationButton,
  CancelButton,
  Label,
};
