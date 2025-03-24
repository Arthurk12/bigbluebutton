import styled from 'styled-components';
import { lgBorderRadius } from '../../stylesheets/styled-components/general';

type ContainerProps = {
  isResizing: boolean;
  isMinimized: boolean;
};

export const Container = styled.div<ContainerProps>`
  position: absolute;
  pointer-events: inherit;
  background: var(--color-black);
  z-index: 5;
  display: grid;
  border-radius: ${lgBorderRadius};
  ${({ isResizing }) => isResizing && `
    pointer-events: none;
  `}
  ${({ isMinimized }) => isMinimized && `
    display: none;
  `}
`;

export default {
  Container,
};
