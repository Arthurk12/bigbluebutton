import {
  useRef,
} from 'react';
import {
  useLazyQuery,
} from '@apollo/client';
import Auth from '/imports/ui/services/auth';
import {
  AUDIO_GROUP_USERS,
  AUDIO_GROUP_USERS_SUBSCRIPTION,
  MY_AUDIO_GROUPS,
  MY_AUDIO_GROUPS_SUBSCRIPTION,
  AUDIO_GROUPS,
  AUDIO_GROUPS_SUBSCRIPTION,
} from '/imports/ui/components/livekit/audio-groups/queries';
import logger from '/imports/startup/client/logger';
import createUseSubscription from '/imports/ui/core/hooks/createUseSubscription';

export const useAudioGroupUsersSubscription = createUseSubscription(
  AUDIO_GROUP_USERS_SUBSCRIPTION,
  {},
  true,
);

export const useMyAudioGroupsSubscription = createUseSubscription(
  MY_AUDIO_GROUPS_SUBSCRIPTION,
  { variables: { userId: Auth.userID } },
  true,
);

export const useAudioGroupsSubscription = createUseSubscription(
  AUDIO_GROUPS_SUBSCRIPTION,
  {},
  true,
);

export const useMyAudioGroupsQuery = () => useLazyQuery(MY_AUDIO_GROUPS, {
  variables: {
    userId: Auth.userID,
  },
});

export const useAudioGroupsQuery = () => useLazyQuery(AUDIO_GROUPS);

export const useAudioGroupUsersQuery = () => useLazyQuery(AUDIO_GROUP_USERS);

export const useAudioGroups = () => {
  const { data, loading, errors } = useAudioGroupsSubscription();
  const audioGroups = useRef([]);

  if (loading) return audioGroups.current;

  if (errors) {
    errors.forEach((error) => {
      logger.error({
        logCode: 'audio_groups_sub_error',
        extraInfo: {
          errorMessage: error.message,
        },
      }, 'Audio groups subscription failed.');
    });
  }

  if (!data) {
    audioGroups.current = [];
    return audioGroups.current;
  }

  // @ts-ignore
  audioGroups.current = data.map(({ groupId }) => groupId);

  return audioGroups.current;
};

export const useMyAudioGroups = () => {
  const { data, loading, errors } = useMyAudioGroupsSubscription();
  const myAudioGroups = useRef([]);

  if (loading) return myAudioGroups.current;

  if (errors) {
    errors.forEach((error) => {
      logger.error({
        logCode: 'my_audio_groups_sub_error',
        extraInfo: {
          errorMessage: error.message,
        },
      }, 'My audio groups subscription failed.');
    });
  }

  if (!data) {
    myAudioGroups.current = [];
    return myAudioGroups.current;
  }

  // @ts-ignore
  myAudioGroups.current = data.map(({ groupId }) => groupId);

  return myAudioGroups.current;
};

export const useAudioGroupUsers = () => {
  const { data, loading, errors } = useAudioGroupUsersSubscription();
  const audioGroupUsers = useRef([]);

  if (loading) return audioGroupUsers.current;

  if (errors) {
    errors.forEach((error) => {
      logger.error({
        logCode: 'audio_group_users_sub_error',
        extraInfo: {
          errorMessage: error.message,
        },
      }, 'Audio group users subscription failed.');
    });
  }
  if (!data) {
    audioGroupUsers.current = [];
    return audioGroupUsers.current;
  }

  const users = data.map(({
    // @ts-ignore
    userId, groupId, participantType, active,
  }) => ({
    userId,
    groupId,
    participantType,
    active,
  }));
  // @ts-ignore
  audioGroupUsers.current = users;

  return audioGroupUsers.current;
};
