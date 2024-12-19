export type AudioGroupParticipant = {
  id: string;
  participantType: string;
  active: string;
}

export type AudioGroup = {
  id: string;
  senders: AudioGroupParticipant[];
  receivers: AudioGroupParticipant[];
}
