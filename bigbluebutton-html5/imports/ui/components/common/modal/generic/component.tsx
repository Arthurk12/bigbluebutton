import React, { useId, useLayoutEffect } from 'react';
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
  /** Custom inline styles applied directly to the modal content element. */
  contentStyle?: React.CSSProperties;
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
  contentStyle,
  'data-test': dataTest,
}) => {
  const uid = useId().replace(/:/g, '');
  // Unique attribute used as a DOM marker rendered inside the modal body.
  // Since the marker is always a descendant of its own ReactModal__Overlay,
  // we can use closest() to find the overlay without any snapshot/diff logic.
  const markerAttr = `data-bbb-modal-${uid}`;
  const styleTagId = `modal-style-${uid}`;

  useLayoutEffect(() => {
    if (!isOpen) {
      document.getElementById(styleTagId)?.remove();
      return undefined;
    }

    // Inject the contentStyle CSS rule immediately — before the overlay appears.
    // We use :has([markerAttr]) so the rule self-targets the right content element
    // without needing to reference the overlay element at all.
    // When react-modal's ModalPortal does its async setState({isOpen:true}) and
    // adds the overlay to the DOM, the rule is already in <head> → zero flash.
    if (contentStyle) {
      let styleEl = document.getElementById(styleTagId) as HTMLStyleElement | null;
      if (!styleEl) {
        styleEl = document.createElement('style');
        styleEl.id = styleTagId;
        document.head.appendChild(styleEl);
      }
      const rules = (Object.entries(contentStyle) as [string, string][])
        .map(([k, v]) => `${k.replace(/([A-Z])/g, (m) => `-${m.toLowerCase()}`)}: ${v} !important;`)
        .join(' ');
      // :has() targets the .ReactModal__Content that contains our unique marker span.
      styleEl.textContent = `.ReactModal__Content:has([${markerAttr}]) { ${rules} }`;
    }

    // priority class and data-test still require the overlay element to exist.
    if (!priority && !dataTest) return undefined;

    const applyClasses = (): boolean => {
      const marker = document.querySelector(`[${markerAttr}]`);
      if (!marker) return false;
      const overlay = marker.closest('.ReactModal__Overlay');
      if (!overlay) return false;
      if (priority) overlay.classList.add(`modal-${priority}`);
      const content = overlay.querySelector<HTMLElement>('.ReactModal__Content');
      if (content && dataTest) content.setAttribute('data-test', dataTest);
      return true;
    };

    const observer = new MutationObserver(() => {
      if (applyClasses()) observer.disconnect();
    });
    observer.observe(document.body, { childList: true, subtree: true });
    applyClasses();

    // eslint-disable-next-line consistent-return
    return () => observer.disconnect();
  }, [isOpen, priority, dataTest, contentStyle]);

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
    >
      {/* Hidden marker used to locate this instance's overlay via closest(). */}
      {/* eslint-disable-next-line react/jsx-props-no-spreading */}
      <span aria-hidden="true" style={{ display: 'none' }} {...{ [markerAttr]: '' }} />
      {children}
    </BBBModal>
  );
};

export default GenericModal;
