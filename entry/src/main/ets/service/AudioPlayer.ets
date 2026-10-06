import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants, sleep } from './Constants';
import { REFERER, USER_AGENT } from './BiliService';

// 流式播放器级缓冲时长（秒）：首包出声与缓冲平滑的平衡点，取 3~5s 区间中值
const STREAM_BUFFER_SECONDS: number = 4;

export class AudioPlayer {
  private avPlayer: media.AVPlayer | undefined = undefined;
  private playerState: string = 'idle';
  private _isPlaying: boolean = false;
  private _currentTime: number = 0;
  private _duration: number = 0;
  private _isPrepared: boolean = false;
  private desiredRate: number = 1.0;
  // 实例代际号（US2）：每次重建/销毁递增；setupCallbacks 捕获当代代际，
  // 回调先比对代际再更新共享状态，杜绝旧实例残余事件（timeUpdate/stateChange 等）串扰新剧集
  private generation: number = 0;
  onStateChange: ((state: string) => void) | undefined = undefined;
  onTimeUpdate: ((time: number) => void) | undefined = undefined;
  onError: ((msg: string) => void) | undefined = undefined;
  onAudioInterrupt: ((eventType: 'INTERRUPT' | 'END_INTERRUPT') => void) | undefined = undefined;

  get isPlaying(): boolean { return this._isPlaying; }
  get currentTime(): number { return this._currentTime; }
  get duration(): number { return this._duration; }
  get isPrepared(): boolean { return this._isPrepared; }

  private setupCallbacks(): void {
    if (this.avPlayer === undefined) return;
    const gen: number = this.generation;
    this.avPlayer.on('stateChange', (state: string) => {
      if (gen !== this.generation) return;
      this.playerState = state;
      if (state === 'prepared') {
        this._isPrepared = true;
        if (this.avPlayer !== undefined) {
          this._duration = this.avPlayer.duration;
          try {
            this.avPlayer.setPlaybackRate(this.desiredRate);
          } catch (e) {}
        }
      } else if (state === 'playing') {
        this._isPlaying = true;
      } else if (state === 'paused') {
        this._isPlaying = false;
      } else if (state === 'stopped') {
        this._isPlaying = false;
        this._isPrepared = false;
      } else if (state === 'completed') {
        this._isPlaying = false;
      } else if (state === 'idle') {
        this._isPlaying = false;
        this._isPrepared = false;
      } else if (state === 'released') {
        this._isPlaying = false;
        this._isPrepared = false;
        this.avPlayer = undefined;
      }
      if (this.onStateChange !== undefined) {
        this.onStateChange(state);
      }
    });
    this.avPlayer.on('timeUpdate', (time: number) => {
      if (gen !== this.generation) return;
      this._currentTime = time;
      if (this.onTimeUpdate !== undefined) {
        this.onTimeUpdate(time);
      }
    });
    this.avPlayer.on('error', (err: BusinessError) => {
      if (gen !== this.generation) return;
      this.playerState = 'error';
      this._isPrepared = false;
      this._isPlaying = false;
      if (this.onError !== undefined) {
        this.onError(`Player error: ${err.code} - ${err.message}`);
      }
    });
    this.avPlayer.on('audioInterrupt', (event: audio.InterruptEvent) => {
      if (gen !== this.generation) return;
      hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG,
        'audioInterrupt eventType=%{public}d forceType=%{public}d hintType=%{public}d',
        Number(event.eventType), Number(event.forceType), Number(event.hintType));
      try {
        if (this.onAudioInterrupt !== undefined) {
          const isInterrupt: boolean = Number(event.eventType) === 1;
          this.onAudioInterrupt(isInterrupt ? 'INTERRUPT' : 'END_INTERRUPT');
        }
      } catch (e) {}
    });
  }

  private async waitForState(targetState: string, timeoutMs: number): Promise<void> {
    const startTime: number = Date.now();
    while (this.playerState !== targetState) {
      if (Date.now() - startTime > timeoutMs) {
        throw new Error(`waitForState timeout: want ${targetState}, got ${this.playerState}`);
      }
      await sleep(30);
    }
  }

  // 换源前公共重建：释放旧实例、复位状态标志，新建 AVPlayer 并挂回调
  private async recreatePlayer(): Promise<media.AVPlayer> {
    // 重建即换代际：旧实例（含尚未完成异步 release 的残余回调）立即失效
    this.generation++;
    if (this.avPlayer !== undefined) {
      try {
        this.avPlayer.off('stateChange');
        this.avPlayer.off('timeUpdate');
        this.avPlayer.off('error');
        this.avPlayer.off('audioInterrupt');
      } catch (e) {}
      try { await this.avPlayer.release(); } catch (e) {}
      this.avPlayer = undefined;
    }

    this._isPrepared = false;
    this._isPlaying = false;
    this._currentTime = 0;
    this._duration = 0;
    this.playerState = 'idle';

    const player: media.AVPlayer = await media.createAVPlayer();
    this.avPlayer = player;
    player.audioRendererInfo = {
      content: audio.ContentType.CONTENT_TYPE_MUSIC,
      usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
      rendererFlags: 0
    };
    try {
      player.audioInterruptMode = audio.InterruptMode.INDEPENDENT_MODE;
    } catch (e) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'set audioInterruptMode failed');
    }
    this.setupCallbacks();
    return player;
  }

  // 远程流式数据源（US2）：CDN 直链 + Referer/UA 请求头，播放器内核边下边播、按需分段拉取（seek 由内核处理）；
  // 每次调用全量重建 AVPlayer，失败重试安全；prepared/error 等回调复用既有订阅机制
  async setStreamSource(url: string): Promise<void> {
    const player: media.AVPlayer = await this.recreatePlayer();

    const headers: Record<string, string> = {
      'Referer': REFERER,
      'User-Agent': USER_AGENT,
    };
    const mediaSource: media.MediaSource = media.createMediaSourceWithUrl(url, headers);
    const strategy: media.PlaybackStrategy = {
      preferredBufferDuration: STREAM_BUFFER_SECONDS,
    };

    await player.setMediaSource(mediaSource, strategy);

    await this.waitForState('initialized', 8000);

    await player.prepare();
  }

  async play(): Promise<void> {
    if (this.avPlayer !== undefined && this._isPrepared) {
      try {
        await this.avPlayer.play();
      } catch (e) {}
    }
  }

  async pause(): Promise<void> {
    if (this.avPlayer !== undefined && this._isPlaying) {
      try {
        await this.avPlayer.pause();
      } catch (e) {}
    }
  }

  async stop(): Promise<void> {
    if (this.avPlayer !== undefined) {
      try { await this.avPlayer.stop(); } catch (e) {}
    }
  }

  async resetPlayer(): Promise<void> {
    this.generation++;
    if (this.avPlayer !== undefined) {
      try {
        this.avPlayer.off('stateChange');
        this.avPlayer.off('timeUpdate');
        this.avPlayer.off('error');
        this.avPlayer.off('audioInterrupt');
      } catch (e) {}
      try { await this.avPlayer.release(); } catch (e) {}
      this.avPlayer = undefined;
    }
    this._isPlaying = false;
    this._isPrepared = false;
    this._currentTime = 0;
    this._duration = 0;
    this.playerState = 'idle';
  }

  async seek(timeMs: number): Promise<void> {
    if (this.avPlayer !== undefined && this._isPrepared) {
      this.avPlayer.seek(timeMs);
    }
  }

  setRate(rate: number): void {
    this.desiredRate = rate;
    if (this.avPlayer !== undefined && this._isPrepared) {
      try {
        this.avPlayer.setPlaybackRate(rate);
      } catch (e) {}
    }
  }

  async release(): Promise<void> {
    this.generation++;
    if (this.avPlayer !== undefined) {
      try {
        this.avPlayer.off('stateChange');
        this.avPlayer.off('timeUpdate');
        this.avPlayer.off('error');
        this.avPlayer.off('audioInterrupt');
      } catch (e) {}
      try { await this.avPlayer.release(); } catch (e) {}
      this.avPlayer = undefined;
    }
  }
}
