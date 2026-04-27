import React from 'react';
import GenericModal from '/imports/ui/components/common/modal/generic/component';
import { defineMessages, useIntl } from 'react-intl';
import FallbackView from '../fallback-view/component';

const intlMessages = defineMessages({
  ariaTitle: {
    id: 'app.error.fallback.modal.ariaTitle',
    description: 'title announced when fallback modal is showed',
  },
});

const FallbackModal = ({ error }) => {
  const intl = useIntl();
  return (
    <GenericModal
      priority="medium"
      shouldCloseOnEsc={false}
      shouldCloseOnOverlayClick={false}
      onRequestClose={() => {}}
      contentLabel={intl.formatMessage(intlMessages.ariaTitle)}
      isOpen={!!error}
    >
      <FallbackView {...{ error }} />
    </GenericModal>
  );
};

export default FallbackModal;
