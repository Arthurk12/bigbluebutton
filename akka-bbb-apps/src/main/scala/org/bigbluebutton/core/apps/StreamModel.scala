package org.bigbluebutton.core.apps

object StreamModel {
  def setStream(
      model:        StreamModel,
      state:        Boolean,
      streamUrl:    String      = "",
      streamType:   String      = "",
      videoUrl:     String      = "",
      sharedSecret: String      = "",
      showCaptions: Boolean     = true,
  ): Unit = {
    model.state = state
    model.streamUrl = streamUrl
    model.streamType = streamType
    model.videoUrl = videoUrl
    model.sharedSecret = sharedSecret
    model.showCaptions = showCaptions
  }

  def setShowCaptions(model: StreamModel, showCaptions: Boolean): Unit = {
    model.showCaptions = showCaptions
  }

  def getState(model: StreamModel): Boolean = {
    model.state
  }

  def getStreamUrl(model: StreamModel): String = {
    model.streamUrl
  }

  def getStreamType(model: StreamModel): String = {
    model.streamType
  }

  def getVideoUrl(model: StreamModel): String = {
    model.videoUrl
  }

  def getShowCaptions(model: StreamModel): Boolean = {
    model.showCaptions
  }
}

class StreamModel {
  private var state: Boolean = false
  private var streamUrl: String = ""
  private var streamType: String = ""
  private var videoUrl: String = ""
  private var sharedSecret: String = ""
  private var showCaptions: Boolean = true
}
