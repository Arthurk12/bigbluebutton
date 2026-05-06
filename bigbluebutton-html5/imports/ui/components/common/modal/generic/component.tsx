import React, { useId, useLayoutEffect, useRef } from 'react';
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
  const modalClass = `modal-uid-${uid}`;
  const styleTagId = `modal-style-${uid}`;
  const overlayRef = useRef<Element | null>(null);
  const prevIsOpenRef = useRef(false);
  const overlaySnapshotRef = useRef<Set<Element>>(new Set());

  // Snapshot taken in the render phase (before BBBModal portal is added to DOM),
  // so the new overlay can be identified by diff in the useLayoutEffect below.
  if (isOpen && !prevIsOpenRef.current) {
    overlayRef.current = null; // force re-discovery on every (re-)open
    overlaySnapshotRef.current = new Set(
      Array.from(document.body.querySelectorAll('.ReactModal__Overlay')),
    );
  }
  prevIsOpenRef.current = isOpen;

  // useLayoutEffect fires synchronously after the DOM commit, so react-modal's
  // portal (added via createPortal in the same commit) is already in the DOM.
  // This eliminates the MutationObserver race window present with useEffect.
  useLayoutEffect(() => {
    if (!isOpen) {
      overlayRef.current = null;
      document.getElementById(styleTagId)?.remove();
      return undefined;
    }

    const applyToOverlay = (overlay: Element) => {
      overlayRef.current = overlay;

      // Priority class for z-index management via modals.css.
      if (priority) overlay.classList.add(`modal-${priority}`);

      const content = overlay.querySelector<HTMLElement>('.ReactModal__Content');
      if (content && dataTest) content.setAttribute('data-test', dataTest);

      if (contentStyle) {
        // Scope the style rule to this specific overlay instance.
        overlay.classList.add(modalClass);

        // BBBModal hardcodes style:h with maxWidth:'90vw' via react-modal, so
        // Object.assign on inline styles would be overridden on every re-render.
        // Injecting CSS with !important is the only reliable override.
        let styleEl = document.getElementById(styleTagId) as HTMLStyleElement | null;
        if (!styleEl) {
          styleEl = document.createElement('style');
          styleEl.id = styleTagId;
          document.head.appendChild(styleEl);
        }
        const rules = (Object.entries(contentStyle) as [string, string][])
          .map(([k, v]) => `${k.replace(/([A-Z])/g, (m) => `-${m.toLowerCase()}`)}: ${v} !important;`)
          .join(' ');
        styleEl.textContent = `.${modalClass} .ReactModal__Content { ${rules} }`;
      }
    };

    // If the overlay for this instance was already identified and is still in
    // the DOM, reuse it (effect re-running because a dep like contentStyle changed).
    if (overlayRef.current && document.body.contains(overlayRef.current)) {
      applyToOverlay(overlayRef.current);
      return undefined;
    }
    overlayRef.current = null; // discard stale ref if element was removed

    // Find the overlay that appeared after isOpen became true (diff with snapshot).
    const tryApplyNow = () => {
      const all = Array.from(document.body.querySelectorAll('.ReactModal__Overlay'));
      const newOnes = all.filter((el) => !overlaySnapshotRef.current.has(el));
      const target = newOnes[newOnes.length - 1];
      if (target) { applyToOverlay(target); return true; }
      return false;
    };

    if (tryApplyNow()) return undefined;

    // Overlay not yet committed — observe until it appears.
    // This is a fallback for cases where BBBModal defers its portal.
    const observer = new MutationObserver(() => {
      if (tryApplyNow()) observer.disconnect();
    });
    observer.observe(document.body, { childList: true, subtree: true });

    // eslint-disable-next-line consistent-return
    return () => observer.disconnect();
  }, [isOpen, priority, dataTest, contentStyle]);

  return (
    <div>
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
