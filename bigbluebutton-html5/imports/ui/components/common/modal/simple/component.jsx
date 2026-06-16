import React from 'react';
import PropTypes from 'prop-types';
import GenericModal from '/imports/ui/components/common/modal/generic/component';

const propTypes = {
  title: PropTypes.string,
  contentLabel: PropTypes.string,
  dismiss: PropTypes.shape({
    callback: PropTypes.func,
  }),
  shouldCloseOnOverlayClick: PropTypes.bool,
  shouldCloseOnEsc: PropTypes.bool,
  modalIsOpen: PropTypes.bool,
  isOpen: PropTypes.bool,
  onRequestClose: PropTypes.func,
  priority: PropTypes.string,
  children: PropTypes.node,
};

const defaultProps = {
  title: '',
  contentLabel: undefined,
  dismiss: { callback: null },
  shouldCloseOnOverlayClick: true,
  shouldCloseOnEsc: true,
  modalIsOpen: false,
  isOpen: false,
  onRequestClose: null,
  priority: undefined,
  children: null,
};

const ModalSimple = ({
  title,
  contentLabel,
  dismiss,
  shouldCloseOnOverlayClick,
  shouldCloseOnEsc,
  modalIsOpen,
  isOpen,
  onRequestClose,
  priority,
  children,
  // legacy props — intentionally ignored (handled by GenericModal/BBBModal internally)
  // eslint-disable-next-line no-unused-vars
  shouldShowCloseButton,
  // eslint-disable-next-line no-unused-vars
  hideBorder,
  // eslint-disable-next-line no-unused-vars
  headerPosition,
  // eslint-disable-next-line no-unused-vars
  width,
  // eslint-disable-next-line no-unused-vars
  height,
  // eslint-disable-next-line no-unused-vars
  padding,
  anchorElement,
  // eslint-disable-next-line no-unused-vars
  setIsOpen,
  ...otherProps
}) => {
  const open = modalIsOpen || isOpen || false;
  const handleClose = onRequestClose || dismiss?.callback || (() => {});

  return (
    <GenericModal
      isOpen={open}
      onRequestClose={handleClose}
      title={title}
      contentLabel={contentLabel || title}
      shouldCloseOnOverlayClick={shouldCloseOnOverlayClick}
      shouldCloseOnEsc={shouldCloseOnEsc}
      priority={priority}
      anchorElement={anchorElement}
      {...otherProps}
    >
      {children}
    </GenericModal>
  );
};

ModalSimple.propTypes = propTypes;
ModalSimple.defaultProps = defaultProps;

export default ModalSimple;
