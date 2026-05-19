import React, { useCallback } from 'react';
import { BBBModal } from '@mconf/bbb-ui-components-react';
import type { ModalPriority } from '@mconf/bbb-ui-components-react';

export type { ModalPriority };

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
  /** Custom inline styles applied directly to the modal content element. */
  contentStyle?: React.CSSProperties;
  /** Test identifier propagated to the modal wrapper for automated testing. */
  'data-test'?: string;
  /**
   * When provided, positions the modal content directly below this element
   * (popover / anchored style). The dark backdrop is preserved.
   * Pass `null` to use the default centred layout (e.g. on mobile).
   */
  anchorElement?: HTMLElement | null;
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
  contentStyle,
  anchorElement,
  'data-test': dataTest,
}) => {
  // contentRef: applied directly to the ReactModal content element via the
  // BBBModal v2.1.0 API (ModalProps now extends ReactModal.Props).
  const contentRefCallback = useCallback((node: HTMLDivElement | null) => {
    if (!node) return;

    if (contentStyle) {
      Object.assign(node.style, contentStyle);
    }

    if (anchorElement) {
      // Position the modal content directly below the anchor element.
      // position:fixed removes the element from the overlay's flex flow so
      // align-items/justify-content no longer affect placement.
      const anchorRect = anchorElement.getBoundingClientRect();
      const anchorCenterX = anchorRect.left + anchorRect.width / 2;
      const modalWidth = 600;
      const left = Math.max(0, anchorCenterX - modalWidth / 2);
      Object.assign(node.style, {
        position: 'fixed',
        top: `${anchorRect.bottom + 10}px`,
        left: `${left}px`,
        overflow: 'visible',
      });
    }

    if (dataTest) {
      node.setAttribute('data-test', dataTest);
    }
  }, [anchorElement, contentStyle, dataTest]);

  return (
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
      contentRef={contentRefCallback}
      priority={priority}
    >
      {children}
    </BBBModal>
  );
};

export default GenericModal;
