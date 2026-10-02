import { avSession } from '@kit.AVSessionKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent, WantAgent, common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Constants } from './Constants';

export type MediaCommandCallback = () => void;

export class MediaSession {
  private static instance: MediaSession | undefined = undefined;

  static getInstance(): MediaSession {
    if (MediaSession.instance === undefined) {
      MediaSession.instance = new MediaSession();
    }
    return MediaSession.instance;
  }

  private session: avSession.AVSession | undefined = undefined;
  private bgRunning: boolean = false;
  private lastAssetId: string = '';

  async init(onPlay: MediaCommandCallback, onPause: MediaCommandCallback,
    onNext: MediaCommandCallback, onPrev: MediaCommandCallback,
    onSeek: (time: number) => void): Promise<void> {
    if (this.session !== undefined) {
      return;
    }
    try {
      const context = getContext() as common.UIAbilityContext;
      this.session = await avSession.createAVSession(context, 'BiliRadioSession', 'audio');
      this.session.on('play', onPlay);
      this.session.on('pause', onPause);
      this.session.on('playNext', onNext);
      this.session.on('playPrevious', onPrev);
      this.session.on('seek', onSeek);
      await this.session.activate();
      hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'AVSession created and activated');
    } catch (err) {
      const error = err as BusinessError;
      this.session = undefined;
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'AVSession init failed: %{public}s', error.message);
    }
  }

  async updateTrack(assetId: string, title: string, durationMs: number, coverUrl: string,
    artist: string): Promise<void> {
    if (this.session === undefined || assetId === '' || this.lastAssetId === assetId) {
      return;
    }
    this.lastAssetId = assetId;
    try {
      const meta: avSession.AVMetadata = {
        assetId: assetId,
        title: title,
        artist: artist,
        duration: durationMs,
        mediaImage: coverUrl,
      };
      await this.session.setAVMetadata(meta);
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'setAVMetadata failed: %{public}s', error.message);
    }
  }

  async updateState(playing: boolean, positionMs: number): Promise<void> {
    if (this.session === undefined) {
      return;
    }
    try {
      const state: avSession.AVPlaybackState = {
        state: playing ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
        position: { elapsedTime: positionMs, updateTime: Date.now() },
      };
      await this.session.setAVPlaybackState(state);
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'setAVPlaybackState failed: %{public}s', error.message);
    }
  }

  async startBackground(): Promise<void> {
    if (this.bgRunning) {
      return;
    }
    try {
      const context = getContext() as common.UIAbilityContext;
      const wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: context.abilityInfo.bundleName,
            abilityName: context.abilityInfo.name,
          }
        ],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
      };
      const agent: WantAgent = await wantAgent.getWantAgent(wantAgentInfo);
      await backgroundTaskManager.startBackgroundRunning(
        context, backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK, agent);
      this.bgRunning = true;
      hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'background continuous task started');
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'startBackgroundRunning failed: %{public}s', error.message);
    }
  }

  async stopBackground(): Promise<void> {
    if (!this.bgRunning) {
      return;
    }
    this.bgRunning = false;
    try {
      const context = getContext() as common.UIAbilityContext;
      await backgroundTaskManager.stopBackgroundRunning(context);
      hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'background continuous task stopped');
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'stopBackgroundRunning failed: %{public}s', error.message);
    }
  }
}
