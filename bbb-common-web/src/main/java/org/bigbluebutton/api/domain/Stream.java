package org.bigbluebutton.api.domain;

public class Stream {
	private final String streamUrl;
	private final String streamType;
	private final String videoUrl;
	private final String sharedSecret;

	public Stream() {
		this.streamUrl = "";
		this.streamType = "";
		this.videoUrl = "";
		this.sharedSecret = "";
	}

	public Stream(String streamUrl, String streamType, String videoUrl, String sharedSecret) {
		this.streamUrl = streamUrl;
		this.streamType = streamType;
		this.videoUrl = videoUrl;
		this.sharedSecret = sharedSecret;
	}

	public Boolean isRunning() {
		return !"".equals(videoUrl);
	}

	public String getStreamUrl() {
		return streamUrl;
	}

	public String getStreamType() {
		return streamType;
	}

	public String getVideoUrl() {
		return videoUrl;
	}
}
