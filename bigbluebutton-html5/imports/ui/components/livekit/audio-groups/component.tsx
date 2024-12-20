// @ts-nocheck
// eslint-ignore no-underscore-dangle
import React, { useEffect } from 'react';
import { useMutation } from '@apollo/client';
import {
  AUDIO_GROUP_CREATE,
  AUDIO_GROUP_DESTROY,
  AUDIO_GROUP_JOIN,
  AUDIO_GROUP_LEAVE,
  AUDIO_GROUP_UPDATE_PARTICIPANT,
} from './mutations';

const AudioGroupsPH: React.FC = () => {
  const [createAudioGroup] = useMutation(AUDIO_GROUP_CREATE);
  const [destroyAudioGroup] = useMutation(AUDIO_GROUP_DESTROY);
  const [joinAudioGroup] = useMutation(AUDIO_GROUP_JOIN);
  const [leaveAudioGroup] = useMutation(AUDIO_GROUP_LEAVE);
  const [updateAudioGroupParticipant] = useMutation(AUDIO_GROUP_UPDATE_PARTICIPANT);

  useEffect(() => {
    window._createAudioGroup = createAudioGroup;
    window._destroyAudioGroup = destroyAudioGroup;
    window._joinAudioGroup = joinAudioGroup;
    window._leaveAudioGroup = leaveAudioGroup;
    window._updateAudioGroupParticipant = updateAudioGroupParticipant;

    return () => {
      delete window._createAudioGroup;
      delete window._destroyAudioGroup;
      delete window._joinAudioGroup;
      delete window._leaveAudioGroup;
      delete window._updateAudioGroupParticipant;
    };
  }, []);

  return null;
};

export default AudioGroupsPH;
