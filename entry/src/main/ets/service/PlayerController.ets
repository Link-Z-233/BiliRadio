import { AudioPlayer } from './AudioPlayer';
import { BiliService } from './BiliService';
import { BiliSession } from './BiliSession';
import { SecureStore } from './SecureStore';
import { AppStore, PlaylistSnapshot } from './AppStore';
import { MediaSession } from './MediaSession';
import { BiliVideo } from '../model/BiliVideo';
import { UnfavoriteRecord } from '../model/UnfavoriteRecord';
import { PlayHistoryItem } from '../model/PlayHistoryItem';

import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from './Constants';
import { NetUtil } from './NetUtil';

export enum PlayMode {
  SEQUENTIAL = 0,
  RANDOM = 1,
  REPEAT_ONE = 2,
  REVERSE = 3
}

export const PLAYBACK_RATES: number[] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

export const PLAY_MODES: PlayMode[] = [
  PlayMode.SEQUENTIAL,
  PlayMode.RANDOM,
  PlayMode.REPEAT_ONE,
  PlayMode.REVERSE
];

// seekBy 连按合并防抖窗口已收敛至 Constants.SEEK_BY_DEBOUNCE_MS（全库唯一常量点）

export class PlayerController {
  private static instance: PlayerController | undefined = undefined;

  static getInstance(): PlayerController {
    if (PlayerController.instance === undefined) {
      PlayerController.instance = new PlayerController();
    }
    return PlayerController.instance;
  }

  playlist: BiliVideo[] = [];
  playlistVersion: number = 0;
  currentIndex: number = -1;
  playMode: PlayMode = PlayMode.SEQUENTIAL;
  playbackRate: number = 1.0;
  isPreparing: boolean = false;
  isPlaying: boolean = false;
  isPrepared: boolean = false;
  currentTime: number = 0;
  duration: number = 0;
  statusMsg: string = '在首页添加订阅，或在播放队列中粘贴BV号开始收听';
  pendingSeekMs: number = 0;
  playWhenReady: boolean = true;
  private pausedByUser: boolean = false;
  // 打断前是否处于播放意图：audioInterrupt INTERRUPT 时记录，END_INTERRUPT 时据此决定是否续播，仅播放会话内有效
  private resumeAfterInterrupt: boolean = false;

  private player: AudioPlayer = new AudioPlayer();
  private mediaSession: MediaSession = MediaSession.getInstance();
  private inited: boolean = false;
  private lastSaveTime: number = 0;
  // 上次向 UI 广播进度时所在的秒数，用于进度 tick 秒级节流
  private lastEmittedSec: number = -1;
  private uiListeners: Array<() => void> = [];
  unfavoriteHistory: UnfavoriteRecord[] = [];
  historyVersion: number = 0;
  playHistory: PlayHistoryItem[] = [];
  playHistoryVersion: number = 0;
  goToPlayerTab: (() => void) | undefined = undefined;
  confirmCellularDownload: (() => Promise<boolean>) | undefined = undefined;
  private loadToken: number = 0;

  static modeLabel(mode: PlayMode): string {
    if (mode === PlayMode.SEQUENTIAL) {
      return '顺序播放';
    }
    if (mode === PlayMode.RANDOM) {
      return '随机播放';
    }
    if (mode === PlayMode.REPEAT_ONE) {
      return '单曲循环';
    }
    return '倒序播放';
  }

  static rateLabel(rate: number): string {
    let label: string = rate.toFixed(2);
    if (label.endsWith('0')) {
      label = label.slice(0, -1);
    }
    return `${label}x`;
  }

  subscribe(fn: () => void): void {
    if (this.uiListeners.indexOf(fn) < 0) {
      this.uiListeners.push(fn);
    }
  }

  private emitUi(): void {
    for (let i = 0; i < this.uiListeners.length; i++) {
      this.uiListeners[i]();
    }
  }

  // 供 UI 层主动请求刷新（如设置开关切换后即时作用于封面/头像等渲染入口）
  refreshUi(): void {
    this.emitUi();
  }

  async init(): Promise<void> {
    if (this.inited) {
      return;
    }
    this.inited = true;
    try {
      await AppStore.init();

      this.unfavoriteHistory = AppStore.loadUnfavoriteHistory();
      this.historyVersion++;

      this.playHistory = AppStore.loadPlayHistoryFile();
      this.playHistoryVersion++;

      BiliService.ensureBuvid().catch((): void => {});

      const cookie: string = await SecureStore.load(Constants.COOKIE_ALIAS);
      if (cookie !== '') {
        BiliSession.getInstance().setCookieString(cookie);
        BiliService.fetchNav().catch((): void => {
          hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'nav verify failed on restore');
        });
      }

      const modeNum: number = AppStore.getNumber(Constants.KEY_PLAY_MODE, 0);
      if (modeNum === 1) {
        this.playMode = PlayMode.RANDOM;
      } else if (modeNum === 2) {
        this.playMode = PlayMode.REPEAT_ONE;
      } else if (modeNum === 3) {
        this.playMode = PlayMode.REVERSE;
      } else {
        this.playMode = PlayMode.SEQUENTIAL;
      }

      const savedRate: number = AppStore.getNumber(Constants.KEY_PLAYBACK_RATE, 1.0);
      if (PLAYBACK_RATES.indexOf(savedRate) >= 0) {
        this.playbackRate = savedRate;
      }
      this.player.setRate(this.playbackRate);

      const snapshot: PlaylistSnapshot = AppStore.loadPlaylistFile();
      let autoStartIndex: number = -1;
      let autoStartPos: number = 0;
      if (snapshot.items.length > 0) {
        this.playlist = snapshot.items;
        this.playlistVersion++;
        const restoreIndex: number = AppStore.getNumber(Constants.KEY_LAST_INDEX, snapshot.lastIndex);
        const restorePos: number = AppStore.getNumber(Constants.KEY_LAST_POS_MS, snapshot.lastPosMs);
        if (restoreIndex >= 0 && restoreIndex < snapshot.items.length) {
          this.currentIndex = restoreIndex;
          this.pendingSeekMs = restorePos;
          this.currentTime = restorePos;
          const item: BiliVideo = snapshot.items[restoreIndex];
          this.duration = item.duration > 0 ? item.duration * 1000 : 0;
          autoStartIndex = restoreIndex;
          autoStartPos = restorePos;
        }
      }

      this.player.onStateChange = (state: string): void => {
        this.onPlayerState(state);
      };
      this.player.onTimeUpdate = (time: number): void => {
        if (this.isPreparing) {
          return;
        }
        this.onPlayerTime(time);
      };
      this.player.onError = (msg: string): void => {
        this.isPreparing = false;
        this.isPrepared = false;
        this.isPlaying = false;
        this.statusMsg = `播放错误: ${msg}`;
        this.mediaSession.updateState(false, this.currentTime);
        this.mediaSession.stopBackground();
        this.emitUi();
      };
      this.player.onAudioInterrupt = (eventType: 'INTERRUPT' | 'END_INTERRUPT'): void => {
        if (eventType === 'INTERRUPT') {
          // isPlaying 在打断瞬间可能已被系统先置 false，改判「用户是否主动暂停过」更可靠
          this.resumeAfterInterrupt = this.isPlaying || !this.pausedByUser;
          hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG,
            'audioInterrupt INTERRUPT resumeAfterInterrupt=%{public}d', this.resumeAfterInterrupt ? 1 : 0);
        } else {
          const resumeEnabled: boolean = AppStore.getNumber(Constants.KEY_INTERRUPT_RESUME, 0) === 1;
          hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG,
            'audioInterrupt END_INTERRUPT enabled=%{public}d resumeFlag=%{public}d',
            resumeEnabled ? 1 : 0, this.resumeAfterInterrupt ? 1 : 0);
          if (resumeEnabled && this.resumeAfterInterrupt) {
            this.playRequest();
          }
          this.resumeAfterInterrupt = false;
        }
      };

      this.mediaSession.init(
        (): void => { this.playRequest(); },
        (): void => { this.pauseRequest(); },
        (): void => { this.next(); },
        (): void => { this.prev(); },
        (time: number): void => { this.seek(time); },
        // US8：媒体控制中心快进/快退按钮走既有 seekBy 防抖路径
        (): void => { this.seekBy(Constants.SEEK_STEP_MS); },
        (): void => { this.seekBy(-Constants.SEEK_STEP_MS); },
      ).catch((): void => {});

      if (autoStartIndex >= 0 && AppStore.getNumber(Constants.KEY_AUTO_PLAY_ON_START, 0) === 1) {
        this.statusMsg = '自动继续播放上次进度';
        this.playIndex(autoStartIndex, autoStartPos).catch((): void => {});
      }

      BiliService.cleanCache('');
    } catch (e) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'init failed');
    }
    this.emitUi();
  }

  private onPlayerState(state: string): void {
    hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'player state: %{public}s, playWhenReady=%{public}d',
      state, this.playWhenReady ? 1 : 0);
    if (state === 'prepared') {
      this.isPrepared = true;
      this.isPreparing = false;
      this.duration = this.player.duration;
      if (this.playWhenReady) {
        this.player.play();
      } else {
        if (this.pendingSeekMs > 0 && this.pendingSeekMs < this.duration) {
          this.currentTime = this.pendingSeekMs;
          this.player.seek(this.pendingSeekMs);
        }
        this.pendingSeekMs = 0;
        this.statusMsg = '已加载完成，处于暂停状态';
        this.mediaSession.updateState(false, this.currentTime);
      }
    } else if (state === 'playing') {
      this.isPlaying = true;
      this.isPreparing = false;
      if (this.pendingSeekMs > 0) {
        const seekTo: number = this.pendingSeekMs;
        this.pendingSeekMs = 0;
        if (seekTo < this.duration) {
          this.player.seek(seekTo);
        }
      }
      this.statusMsg = '';
      this.mediaSession.updateState(true, this.currentTime);
      this.mediaSession.startBackground();
      // 播放历史：仅在 AVPlayer 真实出声（playing，含暂停后恢复）时记录
      if (this.currentIndex >= 0 && this.currentIndex < this.playlist.length) {
        this.recordOnPlaying(this.playlist[this.currentIndex]);
      }
    } else if (state === 'paused') {
      this.isPlaying = false;
      this.persistProgress();
      this.mediaSession.updateState(false, this.currentTime);
    } else if (state === 'completed') {
      this.isPlaying = false;
      this.mediaSession.updateState(false, this.currentTime);
      this.handleCompleted();
    } else if (state === 'idle' || state === 'stopped') {
      this.isPrepared = false;
      this.isPlaying = false;
      this.mediaSession.updateState(false, this.currentTime);
      this.mediaSession.stopBackground();
    }
    this.emitUi();
  }

  private handleCompleted(): void {
    if (this.isPreparing) {
      return;
    }
    if (this.pausedByUser) {
      this.statusMsg = '播放结束';
      return;
    }
    if (this.playMode === PlayMode.REPEAT_ONE) {
      this.player.play();
      return;
    }
    // US7：顺序模式播到最后一集 / 倒序模式回到第一集时停止，不回绕到另一端（手动切歌仍经 next() 回绕）
    const lastIndex: number = this.playlist.length - 1;
    if (lastIndex >= 0 &&
      ((this.playMode === PlayMode.SEQUENTIAL && this.currentIndex >= lastIndex) ||
        (this.playMode === PlayMode.REVERSE && this.currentIndex <= 0))) {
      this.statusMsg = '播放结束';
      return;
    }
    this.next();
  }

  private onPlayerTime(time: number): void {
    // seekBy 防抖期间保持乐观进度，避免播放 tick 将进度拉回旧位置（既有 seek 不经此窗口，语义不变）
    if (this.seekByTimerId >= 0) {
      return;
    }
    this.currentTime = time;
    const now: number = Date.now();
    if (now - this.lastSaveTime > Constants.PROGRESS_SAVE_INTERVAL_MS) {
      this.lastSaveTime = now;
      this.persistProgress();
      this.mediaSession.updateState(this.isPlaying, time);
    }
    // 进度 UI（时间文本/进度条）只需秒级刷新：仅秒变化时广播，
    // 避免 100ms 级播放 tick 每次全量通知 4 个订阅页面
    const sec: number = Math.floor(time / 1000);
    if (sec !== this.lastEmittedSec) {
      this.lastEmittedSec = sec;
      this.emitUi();
    }
  }

  private persistProgress(): void {
    if (this.currentIndex >= 0 && this.currentIndex < this.playlist.length) {
      AppStore.putNumber(Constants.KEY_LAST_INDEX, this.currentIndex);
      AppStore.putNumber(Constants.KEY_LAST_POS_MS, this.currentTime);
    }
  }

  // 元数据回填（US2）：cid/UP 主/播放量/发布时间/简介写回队列条目并刷新 UI
  private applyTrackMeta(item: BiliVideo, video: BiliVideo): void {
    if (video.cid > 0) {
      item.cid = video.cid;
    }
    if (video.ownerName !== '') {
      item.ownerMid = video.ownerMid;
      item.ownerName = video.ownerName;
      item.ownerFace = video.ownerFace;
    }
    if (video.view > 0) {
      item.view = video.view;
    }
    if (video.pubdate > 0) {
      item.pubdate = video.pubdate;
    }
    if (video.desc !== '') {
      item.desc = video.desc;
    }
    this.emitUi();
  }

  // 缓存秒播路径的后台元数据刷新：不阻塞本地文件开播
  private enrichTrackMeta(item: BiliVideo, token: number): void {
    BiliService.fetchVideoInfo(item.bvid).then((video: BiliVideo): void => {
      if (token !== this.loadToken) {
        return;
      }
      this.applyTrackMeta(item, video);
    }).catch((): void => {});
  }

  // 流式开播带重试（US2）：同一 URL 重试一次仍失败则轮换下一备选直链；全部失败抛最后错误，
  // 由 playIndex 统一提示，播放队列与列表状态不受影响
  private async openStreamWithRetry(urls: string[]): Promise<void> {
    let lastError: Error = new Error('No stream URL');
    for (let i = 0; i < urls.length; i++) {
      for (let attempt = 0; attempt < 2; attempt++) {
        try {
          hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG,
            'try stream url %{public}d/%{public}d attempt %{public}d', i + 1, urls.length, attempt + 1);
          await this.player.setStreamSource(urls[i]);
          return;
        } catch (err) {
          const error = err as BusinessError;
          lastError = new Error(error.message);
          hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG,
            'stream open failed: %{public}s', error.message);
        }
      }
    }
    throw lastError;
  }

  async loadPlaylistAndPlay(items: BiliVideo[], startIndex: number): Promise<void> {
    // 追加去重：过滤掉 bvid 已在歌单中的项，避免重复
    const toAdd: BiliVideo[] = [];
    let skipped: number = 0;
    for (let i = 0; i < items.length; i++) {
      if (this.indexOfBvid(items[i].bvid) >= 0) {
        skipped++;
      } else {
        toAdd.push(items[i]);
      }
    }

    // 歌单为空：整体生成并开始播放（保持首次生成的随机/顺序起点行为）
    if (this.playlist.length === 0) {
      this.playlist = toAdd.slice(0);
      this.playlistVersion++;
      this.shuffleHistory = [];
      this.forwardHistory = [];
      this.currentIndex = -1;
      this.isPrepared = false;
      this.isPlaying = false;
      this.currentTime = 0;
      this.duration = 0;
      AppStore.savePlaylistFile(this.playlist, startIndex, 0);
      if (toAdd.length > 0) {
        this.statusMsg = `已添加 ${toAdd.length} 首，开始播放`;
        this.emitUi();
        await this.playIndex(startIndex, 0);
      } else {
        this.statusMsg = '所选内容均已在歌单中';
        this.emitUi();
      }
      return;
    }

    // 歌单非空：追加到末尾，不打断当前播放
    for (let i = 0; i < toAdd.length; i++) {
      this.playlist.push(toAdd[i]);
    }
    this.playlistVersion++;
    AppStore.savePlaylistFile(this.playlist, this.currentIndex, this.currentTime);
    let msg: string = `已追加 ${toAdd.length} 首到歌单末尾`;
    if (skipped > 0) {
      msg += `，去重 ${skipped} 首`;
    }
    this.statusMsg = msg;
    this.emitUi();
  }

  async playIndex(index: number, seekMs: number, fromNav: boolean = false): Promise<void> {
    this.resumeAfterInterrupt = false;
    if (index < 0 || index >= this.playlist.length) {
      return;
    }
    if (!fromNav) {
      const currentBvid: string = this.currentIndex >= 0 && this.currentIndex < this.playlist.length
        ? this.playlist[this.currentIndex].bvid : '';
      if (currentBvid !== this.playlist[index].bvid) {
        this.forwardHistory = [];
      }
    }
    this.currentIndex = index;
    const item: BiliVideo = this.playlist[index];
    this.pendingSeekMs = seekMs;
    this.currentTime = seekMs;
    this.duration = item.duration > 0 ? item.duration * 1000 : 0;
    this.isPreparing = true;
    this.isPrepared = false;
    this.isPlaying = false;
    this.playWhenReady = true;
    this.pausedByUser = false;
    this.statusMsg = '正在解析...';
    this.emitUi();
    this.loadToken++;
    const token: number = this.loadToken;
    try {
      // 仅 Wi-Fi 缓存下载门控：开关开且非 Wi-Fi 时，须经 UI 层确认后才放行本次缓存下载
      const wifiOnly: boolean = AppStore.getNumber(Constants.KEY_WIFI_ONLY_DOWNLOAD, 0) === 1;
      if (wifiOnly && !(await NetUtil.isWifi())) {
        let confirmed: boolean = false;
        if (this.confirmCellularDownload !== undefined) {
          try {
            confirmed = await this.confirmCellularDownload();
          } catch (e) {
            confirmed = false;
          }
        }
        if (!confirmed) {
          this.isPreparing = false;
          this.statusMsg = '当前非 Wi-Fi 网络，已取消播放';
          this.emitUi();
          return;
        }
      }
      const preferLow: boolean = AppStore.getNumber(Constants.KEY_PREFER_LOW_BITRATE, 0) === 1;
      // 缓存优先（US2）：本地已有完整缓存文件直接秒播（现状本地播放路径保留）
      const localPath: string = BiliService.cachedAudioPath(item.bvid);
      if (localPath !== '') {
        this.enrichTrackMeta(item, token);
        item.audioUrl = localPath;
        await this.player.setSource(localPath);
      } else {
        // 流式边下边播（US2）：现取直链（不持久化），缓冲态文案取代整段下载百分比；
        // 视频信息只拉一次——先回填元数据拿到 cid，再解析直链
        this.statusMsg = '正在缓冲...';
        this.emitUi();
        const video: BiliVideo = await BiliService.fetchVideoInfo(item.bvid);
        if (token !== this.loadToken) {
          return;
        }
        this.applyTrackMeta(item, video);
        const urls: string[] = await BiliService.resolveAudioUrlFromCid(item.bvid, video.cid, preferLow);
        if (token !== this.loadToken) {
          return;
        }
        await this.openStreamWithRetry(urls);
      }
      if (token !== this.loadToken) {
        return;
      }
      this.mediaSession.updateTrack(item.bvid, item.title,
        item.duration > 0 ? item.duration * 1000 : 0, item.cover, item.ownerName);
      AppStore.savePlaylistFile(this.playlist, this.currentIndex, 0);
      BiliService.cleanCache(localPath);
    } catch (err) {
      if (token !== this.loadToken) {
        return;
      }
      const error = err as BusinessError;
      this.isPreparing = false;
      this.statusMsg = `播放失败: ${error.message}`;
      this.emitUi();
    }
  }

  private randomIndex(): number {
    const len: number = this.playlist.length;
    if (len <= 1) {
      return 0;
    }
    let target: number = Math.floor(Math.random() * len);
    while (target === this.currentIndex) {
      target = Math.floor(Math.random() * len);
    }
    return target;
  }

  private shuffleHistory: string[] = [];
  private forwardHistory: string[] = [];

  private indexOfBvid(bvid: string): number {
    for (let i = 0; i < this.playlist.length; i++) {
      if (this.playlist[i].bvid === bvid) {
        return i;
      }
    }
    return -1;
  }

  private pushShuffleHistory(): void {
    if (this.currentIndex >= 0 && this.currentIndex < this.playlist.length) {
      const bvid: string = this.playlist[this.currentIndex].bvid;
      if (bvid !== '') {
        this.shuffleHistory.push(bvid);
        if (this.shuffleHistory.length > Constants.HISTORY_MAX) {
          this.shuffleHistory.shift();
        }
      }
    }
  }

  private pushForwardHistory(): void {
    if (this.currentIndex >= 0 && this.currentIndex < this.playlist.length) {
      const bvid: string = this.playlist[this.currentIndex].bvid;
      if (bvid !== '') {
        this.forwardHistory.push(bvid);
        if (this.forwardHistory.length > Constants.HISTORY_MAX) {
          this.forwardHistory.shift();
        }
      }
    }
  }

  private takeShufflePrevIndex(): number {
    const currentBvid: string = this.currentIndex >= 0 && this.currentIndex < this.playlist.length
      ? this.playlist[this.currentIndex].bvid : '';
    while (this.shuffleHistory.length > 0) {
      const bvid: string = this.shuffleHistory.pop() ?? '';
      if (bvid === '' || bvid === currentBvid) {
        continue;
      }
      const idx: number = this.indexOfBvid(bvid);
      if (idx >= 0) {
        return idx;
      }
    }
    return -1;
  }

  private takeForwardIndex(): number {
    while (this.forwardHistory.length > 0) {
      const bvid: string = this.forwardHistory.pop() ?? '';
      if (bvid === '') {
        continue;
      }
      const idx: number = this.indexOfBvid(bvid);
      if (idx >= 0) {
        return idx;
      }
    }
    return -1;
  }

  async next(): Promise<void> {
    if (this.playlist.length === 0) {
      return;
    }
    if (this.playMode === PlayMode.RANDOM && !this.isPreparing) {
      const redo: number = this.takeForwardIndex();
      if (redo >= 0) {
        this.pushShuffleHistory();
        await this.playIndex(redo, 0, true);
        return;
      }
    }
    if (!this.isPreparing) {
      this.pushShuffleHistory();
    }
    let target: number = 0;
    if (this.playMode === PlayMode.RANDOM) {
      target = this.randomIndex();
    } else if (this.playMode === PlayMode.REVERSE) {
      target = (this.currentIndex - 1 + this.playlist.length) % this.playlist.length;
    } else {
      target = (this.currentIndex + 1) % this.playlist.length;
    }
    await this.playIndex(target, 0, false);
  }

  async prev(): Promise<void> {
    if (this.playlist.length === 0) {
      return;
    }
    if (this.isPrepared && this.currentTime > Constants.PREV_SEEK_THRESHOLD_MS) {
      this.player.seek(0);
      return;
    }
    if (this.playMode === PlayMode.RANDOM && !this.isPreparing) {
      const target: number = this.takeShufflePrevIndex();
      this.pushForwardHistory();
      if (target >= 0) {
        await this.playIndex(target, 0, true);
      } else {
        await this.playIndex((this.currentIndex - 1 + this.playlist.length) % this.playlist.length, 0, true);
      }
      return;
    }
    let target: number = 0;
    if (this.playMode === PlayMode.REVERSE) {
      target = (this.currentIndex + 1) % this.playlist.length;
    } else {
      target = (this.currentIndex - 1 + this.playlist.length) % this.playlist.length;
    }
    await this.playIndex(target, 0, true);
  }

  async togglePlay(): Promise<void> {
    if (this.isPreparing) {
      if (this.playWhenReady) {
        await this.pauseRequest();
      } else {
        await this.playRequest();
      }
      return;
    }
    if (this.isPlaying) {
      await this.pauseRequest();
    } else {
      await this.playRequest();
    }
  }

  async playRequest(): Promise<void> {
    if (this.isPreparing) {
      this.playWhenReady = true;
      this.pausedByUser = false;
      this.statusMsg = '加载完成后将自动播放';
      this.emitUi();
      return;
    }
    this.pausedByUser = false;
    if (this.isPrepared) {
      await this.player.play();
    } else if (this.currentIndex >= 0) {
      await this.playIndex(this.currentIndex, this.pendingSeekMs);
    } else if (this.playlist.length > 0) {
      await this.playIndex(0, 0);
    }
  }

  async pauseRequest(): Promise<void> {
    this.resumeAfterInterrupt = false;
    if (this.isPreparing) {
      this.playWhenReady = false;
      this.pausedByUser = true;
      await this.player.pause();
      this.isPlaying = false;
      this.statusMsg = '加载完成后将保持暂停';
      this.emitUi();
      return;
    }
    if (this.isPlaying) {
      this.pausedByUser = true;
      await this.player.pause();
      this.isPlaying = false;
      this.persistProgress();
    }
  }

  seek(ms: number): void {
    this.currentTime = ms;
    if (this.isPrepared) {
      this.player.seek(ms);
    } else {
      this.pendingSeekMs = ms;
    }
    this.emitUi();
  }

  // —— ±15s 进度微调（spec FR-013 / plan R3）——
  // 防抖句柄与待提交目标：连按时合并为最终一次 player.seek，避免 AVPlayer seek 风暴
  private seekByTimerId: number = -1;
  private seekByTargetMs: number = 0;

  seekBy(offsetMs: number): void {
    if (this.duration <= 0 || !this.isPrepared) {
      return;
    }
    // 防抖期内以已累积的待提交目标为基数叠加（等价于最新乐观进度，且不受播放 tick 回写影响）
    const base: number = this.seekByTimerId >= 0 ? this.seekByTargetMs : this.currentTime;
    let target: number = base + offsetMs;
    if (target < 0) {
      target = 0;
    }
    if (target > this.duration) {
      target = this.duration;
    }
    this.seekByTargetMs = target;
    // 乐观更新：进度条/时间行立即反映目标位置
    this.currentTime = target;
    this.refreshUi();
    if (this.seekByTimerId >= 0) {
      clearTimeout(this.seekByTimerId);
    }
    this.seekByTimerId = setTimeout((): void => {
      this.seekByTimerId = -1;
      // 到期时曲目可能已切换（isPrepared 被置 false），此时放弃本次微调
      if (this.isPrepared) {
        this.player.seek(this.seekByTargetMs);
      }
    }, Constants.SEEK_BY_DEBOUNCE_MS);
  }

  setPlayMode(mode: PlayMode): void {
    if (mode !== PlayMode.SEQUENTIAL && mode !== PlayMode.RANDOM &&
      mode !== PlayMode.REPEAT_ONE && mode !== PlayMode.REVERSE) {
      return;
    }
    this.playMode = mode;
    AppStore.putNumber(Constants.KEY_PLAY_MODE, this.playMode);
    this.statusMsg = PlayerController.modeLabel(this.playMode);
    this.emitUi();
  }

  setPlaybackRate(rate: number): void {
    if (PLAYBACK_RATES.indexOf(rate) < 0) {
      return;
    }
    this.playbackRate = rate;
    AppStore.putNumber(Constants.KEY_PLAYBACK_RATE, rate);
    this.player.setRate(rate);
    this.statusMsg = `倍速 ${PlayerController.rateLabel(rate)}`;
    this.emitUi();
  }

  async addToPlaylist(bvid: string): Promise<void> {
    const trimmed: string = bvid.trim();
    if (trimmed === '') {
      this.statusMsg = '请输入BV号';
      this.emitUi();
      return;
    }
    if (this.isPreparing) {
      this.statusMsg = '正在准备中，请稍候';
      this.emitUi();
      return;
    }
    for (let i = 0; i < this.playlist.length; i++) {
      if (this.playlist[i].bvid === trimmed) {
        this.statusMsg = '该歌曲已在歌单中';
        this.emitUi();
        await this.playIndex(i, 0);
        return;
      }
    }
    this.isPreparing = true;
    this.statusMsg = '正在解析...';
    this.emitUi();
    try {
      const video: BiliVideo = await BiliService.fetchVideoInfo(trimmed);
      this.playlist.push(video);
      this.playlistVersion++;
      AppStore.savePlaylistFile(this.playlist, this.currentIndex, this.currentTime);
      this.isPreparing = false;
      this.statusMsg = `已添加「${video.title}」`;
      this.emitUi();
      await this.playIndex(this.playlist.length - 1, 0);
    } catch (err) {
      const error = err as BusinessError;
      this.isPreparing = false;
      this.statusMsg = `解析失败: ${error.message}`;
      this.emitUi();
    }
  }

  // 按 bvid 加入歌单并立即播放（已在歌单则直接播放）
  async playDownloadedSong(video: BiliVideo): Promise<void> {
    if (this.isPreparing) {
      this.statusMsg = '正在准备中，请稍候';
      this.emitUi();
      return;
    }
    const idx: number = this.indexOfBvid(video.bvid);
    if (idx >= 0) {
      await this.playIndex(idx, 0);
      return;
    }
    this.playlist.push(video);
    this.playlistVersion++;
    AppStore.savePlaylistFile(this.playlist, this.currentIndex, this.currentTime);
    this.statusMsg = `已添加「${video.title}」`;
    this.emitUi();
    await this.playIndex(this.playlist.length - 1, 0);
  }

  async unfavoriteCurrent(): Promise<void> {
    if (this.currentIndex < 0 || this.currentIndex >= this.playlist.length) {
      return;
    }
    const item: BiliVideo = this.playlist[this.currentIndex];
    if (item.folderIds.length === 0) {
      this.statusMsg = '该视频不在收藏夹中，无法取消收藏';
      this.emitUi();
      return;
    }
    if (!BiliSession.getInstance().isLogged()) {
      this.statusMsg = '取消收藏需要先登录';
      this.emitUi();
      return;
    }
    this.statusMsg = '正在取消收藏...';
    this.emitUi();
    try {
      await BiliService.unfavorite(item.aid, item.folderIds);
      const folderCount: number = item.folderIds.length;
      this.pushHistory(UnfavoriteRecord.fromVideo(item, Date.now()));
      this.playlist.splice(this.currentIndex, 1);
      this.playlistVersion++;
      if (this.playlist.length === 0) {
        this.currentIndex = -1;
        this.isPrepared = false;
        this.isPlaying = false;
        this.currentTime = 0;
        this.duration = 0;
        await this.player.resetPlayer();
        this.statusMsg = '已取消收藏，歌单已空';
        AppStore.savePlaylistFile(this.playlist, -1, 0);
      } else {
        let targetIndex: number = this.currentIndex;
        let restoreForward: boolean = false;
        if (this.playMode === PlayMode.RANDOM) {
          const restore: number = this.takeForwardIndex();
          if (restore >= 0) {
            targetIndex = restore;
            restoreForward = true;
          }
        }
        if (targetIndex < 0 || targetIndex >= this.playlist.length) {
          targetIndex = 0;
        }
        hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG,
          'unfavorite target=%{public}s strategy=%{public}s',
          this.playlist[targetIndex].bvid, restoreForward ? 'forward' : 'successor');
        this.statusMsg = `已从 ${folderCount} 个收藏夹移除`;
        AppStore.savePlaylistFile(this.playlist, targetIndex, 0);
        await this.playIndex(targetIndex, 0, restoreForward);
      }
      this.emitUi();
    } catch (err) {
      const error = err as BusinessError;
      this.statusMsg = `取消收藏失败: ${error.message}`;
      this.emitUi();
    }
  }

  private pushHistory(record: UnfavoriteRecord): void {
    for (let i = this.unfavoriteHistory.length - 1; i >= 0; i--) {
      if (this.unfavoriteHistory[i].bvid === record.bvid) {
        this.unfavoriteHistory.splice(i, 1);
      }
    }
    this.unfavoriteHistory.unshift(record);
    if (this.unfavoriteHistory.length > Constants.HISTORY_MAX) {
      this.unfavoriteHistory = this.unfavoriteHistory.slice(0, Constants.HISTORY_MAX);
    }
    this.historyVersion++;
    AppStore.saveUnfavoriteHistory(this.unfavoriteHistory);
  }

  async refavoriteFromHistory(index: number): Promise<void> {
    if (index < 0 || index >= this.unfavoriteHistory.length) {
      return;
    }
    if (!BiliSession.getInstance().isLogged()) {
      this.statusMsg = '恢复收藏需要先登录';
      this.emitUi();
      return;
    }
    const record: UnfavoriteRecord = this.unfavoriteHistory[index];
    this.statusMsg = '正在恢复收藏...';
    this.emitUi();
    try {
      await BiliService.favorite(record.aid, record.folderIds);
      this.unfavoriteHistory.splice(index, 1);
      this.historyVersion++;
      AppStore.saveUnfavoriteHistory(this.unfavoriteHistory);
      this.statusMsg = `已恢复收藏「${record.title}」`;
      this.emitUi();
    } catch (err) {
      const error = err as BusinessError;
      this.statusMsg = `恢复收藏失败: ${error.message}`;
      this.emitUi();
    }
  }

  clearUnfavoriteHistory(): void {
    this.unfavoriteHistory = [];
    this.historyVersion++;
    AppStore.saveUnfavoriteHistory(this.unfavoriteHistory);
    this.statusMsg = '已清空取消收藏历史';
    this.emitUi();
  }

  private resolveSourceType(video: BiliVideo): number {
    if (video.folderIds.length > 0) {
      return PlayHistoryItem.SOURCE_FAVORITE;
    }
    if (video.seasonKeys.length > 0) {
      return PlayHistoryItem.SOURCE_SEASON;
    }
    return PlayHistoryItem.SOURCE_LOCAL;
  }

  private recordOnPlaying(video: BiliVideo): void {
    try {
      const item: PlayHistoryItem = PlayHistoryItem.fromVideo(
        video, this.resolveSourceType(video), Date.now());
      for (let i = this.playHistory.length - 1; i >= 0; i--) {
        if (this.playHistory[i].bvid === item.bvid) {
          this.playHistory.splice(i, 1);
        }
      }
      this.playHistory.unshift(item);
      if (this.playHistory.length > Constants.HISTORY_MAX) {
        this.playHistory = this.playHistory.slice(0, Constants.HISTORY_MAX);
      }
      this.playHistoryVersion++;
      hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG,
        'recordOnPlaying bvid=%{public}s source=%{public}d total=%{public}d',
        item.bvid, item.sourceType, this.playHistory.length);
      setTimeout((): void => {
        try {
          AppStore.savePlayHistoryFile(this.playHistory);
        } catch (e) {
          hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'savePlayHistoryFile failed');
        }
      }, 0);
    } catch (e) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'recordOnPlaying failed');
    }
  }

  clearPlayHistory(): void {
    this.playHistory = [];
    this.playHistoryVersion++;
    try {
      AppStore.savePlayHistoryFile(this.playHistory);
    } catch (e) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'clearPlayHistory save failed');
    }
    this.emitUi();
  }

  searchLibrary(keyword: string): BiliVideo[] {
    const trimmed: string = keyword.trim();
    if (trimmed === '') {
      return [];
    }
    const kw: string = trimmed.length > Constants.SEARCH_MAX_INPUT_LEN
      ? trimmed.slice(0, Constants.SEARCH_MAX_INPUT_LEN) : trimmed;
    const lowerKw: string = kw.toLowerCase();
    const songs: BiliVideo[] = this.playlist.slice(0);

    const seen: Set<string> = new Set<string>();
    const results: BiliVideo[] = [];
    for (let i = 0; i < songs.length; i++) {
      const v: BiliVideo = songs[i];
      if (v.bvid === '' || seen.has(v.bvid)) {
        continue;
      }
      const titleHit: boolean = v.title.toLowerCase().indexOf(lowerKw) >= 0;
      const ownerHit: boolean = v.ownerName.toLowerCase().indexOf(lowerKw) >= 0;
      if (titleHit || ownerHit) {
        seen.add(v.bvid);
        results.push(v);
      }
    }
    hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG,
      'searchLibrary keyword=%{public}s hits=%{public}d', kw, results.length);
    return results;
  }

  // 播放搜索结果：已在歌单则直接播放，不在则追加到歌单末尾后播放
  async playFromLibraryResult(video: BiliVideo): Promise<void> {
    await this.playDownloadedSong(video);
  }

  async addManyToPlaylist(bvids: string[]): Promise<void> {
    const unique: string[] = [];
    for (let i = 0; i < bvids.length; i++) {
      const bv: string = bvids[i].trim();
      if (bv === '' || unique.indexOf(bv) >= 0) {
        continue;
      }
      unique.push(bv);
    }
    if (unique.length === 0) {
      this.statusMsg = '请输入BV号';
      this.emitUi();
      return;
    }
    if (this.isPreparing) {
      this.statusMsg = '正在准备中，请稍候';
      this.emitUi();
      return;
    }
    let added: number = 0;
    let skipped: number = 0;
    let failed: number = 0;
    const firstAddedIndex: number[] = [];
    for (let i = 0; i < unique.length; i++) {
      this.statusMsg = `正在解析 ${i + 1}/${unique.length}...`;
      this.emitUi();
      let exists: boolean = false;
      for (let j = 0; j < this.playlist.length; j++) {
        if (this.playlist[j].bvid === unique[i]) {
          exists = true;
          break;
        }
      }
      if (exists) {
        skipped++;
        continue;
      }
      try {
        const video: BiliVideo = await BiliService.fetchVideoInfo(unique[i]);
        this.playlist.push(video);
        firstAddedIndex.push(this.playlist.length - 1);
        this.playlistVersion++;
        added++;
        AppStore.savePlaylistFile(this.playlist, this.currentIndex, this.currentTime);
      } catch (err) {
        failed++;
      }
      await new Promise<void>((resolve) => {
        setTimeout(() => { resolve(); }, 300);
      });
    }
    let summary: string = `添加完成：新增 ${added} 首`;
    if (skipped > 0) {
      summary += `，已在歌单 ${skipped}`;
    }
    if (failed > 0) {
      summary += `，失败 ${failed}`;
    }
    this.statusMsg = summary;
    this.emitUi();
    if (firstAddedIndex.length > 0) {
      await this.playIndex(firstAddedIndex[0], 0);
    }
  }

  async removeSelectedFromPlaylist(bvids: string[]): Promise<void> {
    if (bvids.length === 0) {
      return;
    }
    const removingCurrent: boolean = this.currentIndex >= 0 &&
      this.playlist.length > 0 &&
      bvids.indexOf(this.playlist[this.currentIndex].bvid) >= 0;
    let removedBeforeCurrent: number = 0;
    for (let i = 0; i < this.currentIndex && i < this.playlist.length; i++) {
      if (bvids.indexOf(this.playlist[i].bvid) >= 0) {
        removedBeforeCurrent++;
      }
    }
    const kept: BiliVideo[] = this.playlist.filter((v: BiliVideo): boolean => bvids.indexOf(v.bvid) < 0);
    const removedCount: number = this.playlist.length - kept.length;
    if (removedCount === 0) {
      return;
    }
    this.playlist = kept;
    this.playlistVersion++;
    if (this.playlist.length === 0) {
      this.currentIndex = -1;
      this.isPrepared = false;
      this.isPlaying = false;
      this.currentTime = 0;
      this.duration = 0;
      await this.player.resetPlayer();
      this.statusMsg = `已从歌单移除 ${removedCount} 首，歌单已空`;
      AppStore.savePlaylistFile(this.playlist, -1, 0);
    } else if (removingCurrent) {
      this.isPrepared = false;
      this.isPlaying = false;
      let target: number = this.currentIndex - removedBeforeCurrent;
      if (target >= this.playlist.length) {
        target = 0;
      }
      this.statusMsg = `已从歌单移除 ${removedCount} 首`;
      AppStore.savePlaylistFile(this.playlist, target, 0);
      await this.playIndex(target, 0);
    } else {
      this.currentIndex -= removedBeforeCurrent;
      this.statusMsg = `已从歌单移除 ${removedCount} 首`;
      AppStore.savePlaylistFile(this.playlist, this.currentIndex, this.currentTime);
    }
    this.emitUi();
  }
}
