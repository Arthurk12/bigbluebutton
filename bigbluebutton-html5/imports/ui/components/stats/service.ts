import { calculateJitterBufferAverage, getDataType } from '/imports/utils/stats';
import { calculateBitsPerSecond, calculateBitsPerSecondFromMultipleData } from '/imports/ui/components/connection-status/service';
import logger from '/imports/startup/client/logger';
import {
  MetricsData,
  IntervalData,
  NetworkDataArgs,
  Probes,
  PacketsStatistics,
} from './types';

export const LOG_MEDIA_STATS = () => (
  window.meetingClientSettings.public.stats.logMediaStats.enabled);

export const LOG_VIDEO_STATS = () => (
  window.meetingClientSettings.public.stats.logVideoStats.enabled);

const prevStats = {
  bytesSent: 0,
  timestamp: 0,
};

export const formatVideoStats = (stats: Record<string, any> = {}) => {
  const hardcodedStatsOfInterest = [
    'targetBitrate',
    'frameWidth',
    'frameHeight',
    'framesPerSecond',
    'qpSum',
    'bytesSent',
  ];

  try {
    const firstOutboundPeer = Object.entries(stats)
      .filter(([peerId, videoStats]) => peerId !== null && videoStats)
      .map(([peerId, videoStats]) => ({
        peerId,
        outbound: videoStats?.['outbound-rtp'],
      }))
      .find(({ outbound }) => outbound !== undefined);

    if (!firstOutboundPeer) return null;

    const { peerId = null, outbound = {} } = firstOutboundPeer;
    if (!peerId || !outbound) return null;

    const { bytesSent = null, timestamp = null } = outbound;
    if (typeof bytesSent !== 'number' || typeof timestamp !== 'number') return null;

    const deltaBytes = bytesSent - prevStats.bytesSent;
    const deltaTimestamp = timestamp - prevStats.timestamp;
    const bitrateBps = (deltaBytes * 8) / (deltaTimestamp / 1000);
    prevStats.timestamp = timestamp;
    prevStats.bytesSent = bytesSent;

    const desiredStats = Object.fromEntries(
      hardcodedStatsOfInterest
        .filter((key) => outbound[key] !== undefined)
        .map((key) => [key, outbound[key]]),
    );
    desiredStats.bytesSentInBitsPerSecond = Math.round(bitrateBps);
    desiredStats.peerId = peerId;
    return desiredStats;
  } catch (error: unknown) {
    const e = error as Error;
    logger.warn(
      {
        logCode: 'format_video_stats_failed',
        extraInfo: {
          errorMessage: e.message,
        },
      },
      'Exception thrown during video stats formatting.',
    );
    return null;
  }
};

export const buildData = (inboundRTP: RTCInboundRtpStreamStats) => {
  const builtData = {
    packets: {
      received: inboundRTP.packetsReceived || 0,
      lost: inboundRTP.packetsLost || 0,
    },
    bytes: {
      received: inboundRTP.bytesReceived || 0,
    },
    jitter: inboundRTP.jitter || 0,
  };

  return builtData;
};

const diff = (single: boolean, first: number, last: number) => Math.abs((single ? 0 : last) - first);

export const calculateInterval = (stats: IntervalData[]) => {
  const single = stats.length === 1;
  const first = stats[0];
  const last = stats[stats.length - 1];

  return {
    packets: {
      received: diff(single, first.packets.received, last.packets.received),
      lost: diff(single, first.packets.lost, last.packets.lost),
    },
    bytes: {
      received: diff(single, first.bytes.received, last.bytes.received),
    },
    jitter: Math.max(...stats.map((s) => s.jitter)),
  };
};

const calculateLoss = (rate: number) => 1 - (rate / 100);

const calculateMOS = (rate: number) => 1 + (0.035) * rate + (0.000007) * rate * (rate - 60) * (100 - rate);

const calculateRate = (packets: PacketsStatistics) => {
  const { received, lost } = packets;
  const rate = (received > 0) ? ((received - lost) / received) * 100 : 100;
  if (rate < 0 || rate > 100) return 100;
  return rate;
};

const buildResult = (interval: IntervalData): MetricsData => {
  const rate = calculateRate(interval.packets);
  return {
    packets: {
      received: interval.packets.received,
      lost: interval.packets.lost,
    },
    bytes: {
      received: interval.bytes.received,
    },
    jitter: interval.jitter,
    rate,
    loss: calculateLoss(rate),
    MOS: calculateMOS(rate),
  };
};

const clearResult = () => {
  const cleanStats = {
    packets: {
      received: 0,
      lost: 0,
    },
    bytes: {
      received: 0,
    },
    jitter: 0,
    rate: 0,
    loss: 0,
    MOS: 0,
  };

  return cleanStats;
};

export const generateMetrics = (rawProbesStats: Probes) => {
  const statsRead: IntervalData[] = [];
  const { audio } = rawProbesStats;
  audio.forEach((audioProbe) => {
    const inboundRTP = getDataType(audioProbe, 'inbound-rtp')[0];
    const remoteInboundRTP = getDataType(audioProbe, 'remote-inbound-rtp')[0];
    if (inboundRTP || remoteInboundRTP) {
      if (!inboundRTP) {
        logger.debug(
          { logCode: 'stats_missing_inbound_rtc' },
          'Missing local inbound RTC. Using remote instead',
        );
      }
      return statsRead.push(buildData(inboundRTP || remoteInboundRTP));
    }
    return null;
  });
  if (!statsRead || statsRead.length === 0) return clearResult();
  const interval = calculateInterval(statsRead);
  return buildResult(interval);
};

export const calculateMetricsForNetworkData = ({
  previousLastProbe,
  lastProbe,
  allProbes,
}: NetworkDataArgs) => {
  const {
    outbound: audioCurrentUploadRate,
    inbound: audioCurrentDownloadRate,
  } = calculateBitsPerSecond(lastProbe.audio, previousLastProbe.audio);
  const inboundRtp = getDataType(lastProbe.audio, 'inbound-rtp')[0];

  const jitter = inboundRtp
    ? calculateJitterBufferAverage(inboundRtp)
    : 0;

  const packetsLost = inboundRtp
    ? inboundRtp.packetsLost
    : 0;

  const audio = {
    audioCurrentUploadRate,
    audioCurrentDownloadRate,
    jitter,
    packetsLost,
    transportStats: (lastProbe?.audio?.transportStats || {}) as Record<string, unknown>,
  };

  const {
    outbound: webcamsCurrentUploadRate,
    inbound: webcamsCurrentDownloadRate,
  } = calculateBitsPerSecondFromMultipleData(lastProbe?.video,
    previousLastProbe.video);

  const {
    outbound: screenshareCurrentUploadRate,
    inbound: screenshareCurrentDownloadRate,
  } = calculateBitsPerSecond(lastProbe?.screenshare, previousLastProbe?.screenshare);

  const video = {
    videoCurrentUploadRate: webcamsCurrentUploadRate + screenshareCurrentUploadRate,
    videoCurrentDownloadRate: webcamsCurrentDownloadRate + screenshareCurrentDownloadRate,
    screenshareTransportStats: lastProbe.screenshare?.transportStats || {},
  };

  const metrics = generateMetrics(allProbes);
  const networkData = {
    ready: true,
    audio,
    video,
    metrics,
  };

  return networkData;
};

export default calculateMetricsForNetworkData;
