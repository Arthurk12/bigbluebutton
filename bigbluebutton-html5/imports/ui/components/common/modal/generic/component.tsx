import React, { useEffect, useRef } from 'react';
import { BBBModal } from '@mconf/bbb-ui-components-react';

export type ModalPriority = 'low' | 'medium' | 'high';

export interface GenericModalProps {
  /** Controls whether the modal is open. */
  isOpen: boolean;
  /** Callback when the modal requests to close (ESC key, overlay click, close button). */
  onRequestClose: () => void;
  /** Modal title displayed in the header. */
  title?: string;
  /** Accessibility label for the modal content region. Defaults to title. */
  contentLabel?: string;
  /** Shows dividers between header, body, and footer. */
  showDividers?: boolean;
  /** Allows closing the modal by clicking outside it. */
  shouldCloseOnOverlayClick?: boolean;
  /** Allows closing the modal with the ESC key. */
  shouldCloseOnEsc?: boolean;
  /** Enables vertical scrolling inside the modal body. */
  allowScroll?: boolean;
  /** Hides the footer section. */
  noFooter?: boolean;
  /** Custom content rendered in the modal footer. */
  footerContent?: React.ReactNode;
  /** Keeps the footer pinned to the bottom when the body scrolls. */
  stickyFooter?: boolean;
  /** Modal body content. */
  children: React.ReactNode;
  /**
   * Controls z-index priority when multiple modals coexist.
   * Maps to the BBB portal class (`modal-low`, `modal-medium`, `modal-high`).
   */
  priority?: ModalPriority;
  /** Test identifier propagated to the modal wrapper for automated testing. */
  'data-test'?: string;
}

/**
 * GenericModal — the single, unified modal primitive for BigBlueButton HTML5.
 *
 * Built on top of `BBBModal` from `@mconf/bbb-ui-components-react`, it adds
 * BBB-specific concerns (priority-based z-index, `data-test` attribute) while
 * keeping the same clean API surface as the library component.
 *
 * Use this component for all new modals. Prefer migrating existing modals that
 * only need a title + body (and optionally a footer) away from `ModalSimple`.
 *
 * @example
 * <GenericModal
 *   title="Confirm Action"
 *   isOpen={isOpen}
 *   onRequestClose={handleClose}
 *   showDividers
 *   footerContent={<Button onClick={handleClose}>OK</Button>}
 * >
 *   <p>Are you sure you want to proceed?</p>
 * </GenericModal>
 */
const GenericModal: React.FC<GenericModalProps> = ({
  isOpen,
  onRequestClose,
  title,
  contentLabel,
  showDividers = false,
  shouldCloseOnOverlayClick = false,
  shouldCloseOnEsc = true,
  allowScroll = true,
  noFooter = true,
  footerContent = null,
  stickyFooter = true,
  children,
  priority,
  'data-test': dataTest,
}) => {
  const wrapperRef = useRef<HTMLDivElement>(null);

  // Propagate data-test to the rendered modal portal after it opens.
  useEffect(() => {
    if (!isOpen || !dataTest) return;

    const timer = setTimeout(() => {
      const el = document.querySelector('.ReactModal__Content');
      if (el) el.setAttribute('data-test', dataTest);
    }, 0);

    // eslint-disable-next-line consistent-return
    return () => clearTimeout(timer);
  }, [isOpen, dataTest]);

  // Propagate priority class for z-index management via modals.css.
  useEffect(() => {
    if (!isOpen || !priority) return;

    const timer = setTimeout(() => {
      const portal = document.querySelector('.ReactModal__Overlay');
      if (portal) portal.classList.add(`modal-${priority}`);
    }, 0);

    // eslint-disable-next-line consistent-return
    return () => clearTimeout(timer);
  }, [isOpen, priority]);

  return (
    <div ref={wrapperRef}>
      <BBBModal
        isOpen={isOpen}
        onRequestClose={onRequestClose}
        title={title}
        contentLabel={contentLabel ?? title}
        showDividers={showDividers}
        shouldCloseOnOverlayClick={shouldCloseOnOverlayClick}
        shouldCloseOnEsc={shouldCloseOnEsc}
        allowScroll={allowScroll}
        noFooter={noFooter}
        footerContent={footerContent}
        stickyFooter={stickyFooter}
      >
        {children}
      </BBBModal>
    </div>
  );
};

export default GenericModal;
