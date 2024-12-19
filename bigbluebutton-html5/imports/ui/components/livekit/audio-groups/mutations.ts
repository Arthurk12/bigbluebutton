import { gql } from '@apollo/client';

export const AUDIO_GROUP_CREATE = gql`
  mutation AudioGroupCreate($id: String!, $senders: [AudioGroupParticipant], $receivers: [AudioGroupParticipant]) {
    audioGroupCreate(
      id: $id,
      senders: $senders,
      receivers: $receivers
    )
  }
`;

export const AUDIO_GROUP_DESTROY = gql`
  mutation AudioGroupDestroy($id: String!) {
    audioGroupDestroy(
      id: $id
    )
  }
`;

export const AUDIO_GROUP_JOIN = gql`
  mutation AudioGroupJoin($id: String!, $participant: AudioGroupParticipant!) {
    audioGroupJoin(
      id: $id
      participant: $participant
    )
  }
`;

export const AUDIO_GROUP_LEAVE = gql`
  mutation AudioGroupLeave($id: String!, $userId: String!) {
    audioGroupLeave(
      id: $id
      userId: $userId
    )
  }
`;

export const AUDIO_GROUP_UPDATE_PARTICIPANT = gql`
  mutation AudioGroupUpdateParticipant($id: String!, $participant: AudioGroupParticipant!) {
    audioGroupUpdateParticipant(
      id: $id
      participant: $participant
    )
  }
`;

export default {
  AUDIO_GROUP_CREATE,
  AUDIO_GROUP_DESTROY,
  AUDIO_GROUP_JOIN,
  AUDIO_GROUP_LEAVE,
  AUDIO_GROUP_UPDATE_PARTICIPANT,
};
