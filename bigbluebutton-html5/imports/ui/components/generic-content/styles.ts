import styled from 'styled-components';
import { lgBorderRadius } from '../../stylesheets/styled-components/general';

type ContainerProps = {
  preventInteraction: boolean;
  isMinimized: boolean;
};

export const Container = styled.div<ContainerProps>`
  position: absolute;
  pointer-events: inherit;
  background: var(--color-black);
  z-index: 5;
  display: grid;
  border-radius: ${lgBorderRadius};
  ${({ preventInteraction }) => preventInteraction && `
    pointer-events: none;
  `}
  ${({ isMinimized }) => isMinimized && `
    display: none;
  `}
`;

export default {
  Container,
};
