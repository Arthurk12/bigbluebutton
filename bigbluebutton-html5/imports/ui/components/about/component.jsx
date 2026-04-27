import React from 'react';
import { defineMessages, injectIntl, useIntl } from 'react-intl';
import GenericModal from '/imports/ui/components/common/modal/generic/component';

const intlMessages = defineMessages({
  title: {
    id: 'app.about.title',
    description: 'About title label',
  },
  version: {
    id: 'app.about.version',
    description: 'Client version label',
  },
  copyright: {
    id: 'app.about.copyright',
    defaultMessage: (new Date().getFullYear()),
    description: 'Client copyright label',
  },
  version_label: {
    id: 'app.about.version_label',
    description: 'label for version bbb',
  },
});

const AboutComponent = (props) => {
  const {
    settings, isOpen, onRequestClose, priority,
  } = props;
  const intl = useIntl();
  const {
    html5ClientBuild,
    copyright,
    bbbServerVersion,
    displayBbbServerVersion,
  } = settings;

  const showLabelVersion = () => (
    <>
      <br />
      {`${intl.formatMessage(intlMessages.version_label)} ${bbbServerVersion}`}
    </>
  );

  return (
    <GenericModal
      data-test="aboutModalTitleLabel"
      title={intl.formatMessage(intlMessages.title)}
      isOpen={isOpen}
      onRequestClose={onRequestClose}
      priority={priority}
    >
      {`${intl.formatMessage(intlMessages.copyright)} ${copyright}`}
      <br />
      {`${intl.formatMessage(intlMessages.version)} ${html5ClientBuild}`}
      {displayBbbServerVersion ? showLabelVersion() : null}

    </GenericModal>
  );
};

export default injectIntl(AboutComponent);
