import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants, sleep } from './Constants';
import { AppStore } from './AppStore';

export class AudioPlayer {
  private avPlayer: media.AVPlayer | undefined = undefined;
  private playerState: string = 'idle';
  private _isPlaying: boolean = false;
  private _currentTime: number = 0;
  private _duration: number = 0;
  private _isPrepared: boolean = false;
  private currentFd: number = -1;
  private desiredRate: number = 1.0;
  onStateChange: ((state: string) => void) | undefined = undefined;
  onTimeUpdate: ((time: number) => void) | undefined = undefined;
  onError: ((msg: string) => void) | undefined = undefined;
  onAudioInterrupt: ((eventType: 'INTERRUPT' | 'END_INTERRUPT') => void) | undefined = undefined;

  get isPlaying(): boolean { return this._isPlaying; }
  get currentTime(): number { return this._currentTime; }
  get duration(): number { return this._duration; }
  get isPrepared(): boolean { return this._isPrepared; }

  private closeFd(): void {
    if (this.currentFd >= 0) {
      try { fs.closeSync(this.currentFd); } catch (e) {}
      this.currentFd = -1;
    }
  }

  private setupCallbacks(): void {
    if (this.avPlayer === undefined) return;
    this.avPlayer.on('stateChange', (state: string) => {
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
        this.closeFd();
      }
      if (this.onStateChange !== undefined) {
        this.onStateChange(state);
      }
    });
    this.avPlayer.on('timeUpdate', (time: number) => {
      this._currentTime = time;
      if (this.onTimeUpdate !== undefined) {
        this.onTimeUpdate(time);
      }
    });
    this.avPlayer.on('error', (err: BusinessError) => {
      this.playerState = 'error';
      this._isPrepared = false;
      this._isPlaying = false;
      if (this.onError !== undefined) {
        this.onError(`Player error: ${err.code} - ${err.message}`);
      }
    });
    this.avPlayer.on('audioInterrupt', (event: audio.InterruptEvent) => {
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

  async setSource(filePath: string): Promise<void> {
    if (this.avPlayer !== undefined) {
      try {
        this.avPlayer.off('stateChange');
        this.avPlayer.off('timeUpdate');
        this.avPlayer.off('error');
        this.avPlayer.off('audioInterrupt');
      } catch (e) {}
      try { await this.avPlayer.release(); } catch (e) {}
      this.avPlayer = undefined;
      this.closeFd();
    }

    this._isPrepared = false;
    this._isPlaying = false;
    this._currentTime = 0;
    this._duration = 0;
    this.playerState = 'idle';

    this.avPlayer = await media.createAVPlayer();
    this.avPlayer.audioRendererInfo = {
      content: audio.ContentType.CONTENT_TYPE_MUSIC,
      usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
      rendererFlags: 0
    };
    try {
      const coPlay: number = AppStore.getNumber(Constants.KEY_CO_PLAY_WITH_OTHERS, 1);
      this.avPlayer.audioInterruptMode = coPlay === 1
        ? audio.InterruptMode.SHARE_MODE : audio.InterruptMode.INDEPENDENT_MODE;
    } catch (e) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'set audioInterruptMode failed');
    }
    this.setupCallbacks();

    const stat = fs.statSync(filePath);
    const file = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
    this.currentFd = file.fd;
    this.avPlayer.fdSrc = { fd: file.fd, offset: 0, length: stat.size } as media.AVFileDescriptor;

    await this.waitForState('initialized', 8000);

    await this.avPlayer.prepare();
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
    this.closeFd();
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

  applyInterruptMode(coPlayEnabled: boolean): void {
    if (this.avPlayer === undefined) {
      return;
    }
    try {
      this.avPlayer.audioInterruptMode = coPlayEnabled
        ? audio.InterruptMode.SHARE_MODE : audio.InterruptMode.INDEPENDENT_MODE;
      hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG,
        'applyInterruptMode coPlayEnabled=%{public}d', coPlayEnabled ? 1 : 0);
    } catch (e) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'applyInterruptMode failed');
    }
  }

  async release(): Promise<void> {
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
    this.closeFd();
  }
}
