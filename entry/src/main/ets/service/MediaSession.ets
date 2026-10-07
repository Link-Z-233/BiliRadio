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
    onSeek: (time: number) => void,
    onFastForward: MediaCommandCallback, onRewind: MediaCommandCallback): Promise<void> {
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
      this.session.on('fastForward', onFastForward);
      this.session.on('rewind', onRewind);
      await this.session.activate();
      // [API24-COMPAT] setMediaCenterControlType 为 API 26 新增接口，API<26 设备运行时抛 TypeError：
      // 此处独立 try/catch 静默降级（仅媒体控制中心少显示微调按钮，不影响会话本身，避免波及外层 init）；
      // 未来 API 26 基线化后按 PROJECT_NOTES.md 登记统一移除该守卫。
      try {
        const controls: avSession.AVMediaCenterControlType[] =
          ['playPrevious', 'playNext', 'fastForward', 'rewind'];
        await this.session.setMediaCenterControlType(controls);
      } catch (err) {
        const compatError = err as BusinessError;
        hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG,
          'setMediaCenterControlType unsupported on this API level: %{public}s', compatError.message);
      }
      hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'AVSession created and activated');
    } catch (err) {
      const error = err as BusinessError;
      this.session = undefined;
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'AVSession init failed: %{public}s', error.message);
    }
  }

  // force=true 绕过同曲目去重守卫，供设置开关切换等需要重发同曲目元数据的场景（US5）
  async updateTrack(assetId: string, title: string, durationMs: number, coverUrl: string,
    artist: string, force: boolean = false): Promise<void> {
    if (this.session === undefined || assetId === '' || (!force && this.lastAssetId === assetId)) {
      return;
    }
    this.lastAssetId = assetId;
    try {
      const meta: avSession.AVMetadata = {
        assetId: assetId,
        title: title,
        artist: artist,
        duration: durationMs,
      };
      // 空封面（无图模式）不设置 mediaImage 字段，而非传旧值
      if (coverUrl !== '') {
        meta.mediaImage = coverUrl;
      }
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
