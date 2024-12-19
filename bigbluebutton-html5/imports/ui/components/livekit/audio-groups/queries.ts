import { gql } from '@apollo/client';

export const AUDIO_GROUP_USERS = gql`
  query AudioGroupUsers {
    user_audioGroup {
      userId
      groupId
      participantType
      active
    }
  }
`;

export const AUDIO_GROUP_USERS_SUBSCRIPTION = gql`
  subscription AudioGroupUsers {
    user_audioGroup {
      userId
      groupId
      participantType
      active
    }
  }
`;

export const MY_AUDIO_GROUPS = gql`
  query MyAudioGroups($userId: String!) {
    user_audioGroup(
      where: {
        userId: { _eq: $userId },
      },
    ) {
      groupId
      participantType
      active
    }
  }
`;

export const MY_AUDIO_GROUPS_SUBSCRIPTION = gql`
  subscription MyAudioGroups($userId: String!) {
    user_audioGroup(
      where: {
        userId: { _eq: $userId },
      },
    ) {
      groupId
      participantType
      active
    }
  }
`;

export const AUDIO_GROUPS = gql`
  query AudioGroups {
    audioGroup {
      groupId
    }
  }
`;

export const AUDIO_GROUPS_SUBSCRIPTION = gql`
  subscription AudioGroups {
    audioGroup {
      groupId
    }
  }
`;

export default {
  AUDIO_GROUP_USERS,
  AUDIO_GROUP_USERS_SUBSCRIPTION,
  MY_AUDIO_GROUPS,
  MY_AUDIO_GROUPS_SUBSCRIPTION,
  AUDIO_GROUPS,
  AUDIO_GROUPS_SUBSCRIPTION,
};
