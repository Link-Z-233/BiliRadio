import { AudioPlayer } from './AudioPlayer';
import { BiliService } from './BiliService';
import { BiliSession } from './BiliSession';
import { SecureStore } from './SecureStore';
import { AppStore, PlaylistSnapshot } from './AppStore';
import { MediaSession } from './MediaSession';
import { SleepTimerController } from './SleepTimerController';
import { BiliVideo } from '../model/BiliVideo';
import { PlayHistoryItem } from '../model/PlayHistoryItem';
import { AudioTrack, AudioQuality, QualityTier, ResolvedAudio } from '../model/AudioQuality';

import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from './Constants';
import { Logger } from './Logger';
import { NetUtil } from './NetUtil';

export enum PlayMode {
  SEQUENTIAL = 0,
  RANDOM = 1,
  REPEAT_ONE = 2,
  REVERSE = 3
}

export enum EnqueueResult {
  APPENDED = 0,
  STARTED = 1,
  DUPLICATE = 2,
  FAILED = 3
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
  currentItemEnded: boolean = false;
  currentTime: number = 0;
  duration: number = 0;
  statusMsg: string = '在首页添加订阅，或到订阅源详情页播放节目';
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
  // 与 uiListeners 按下标对应的 owner 标识（KI-5）：支撑同 owner 单槽覆盖
  private uiListenerOwners: Array<string> = [];
  playHistory: PlayHistoryItem[] = [];
  playHistoryVersion: number = 0;
  goToPlayerTab: (() => void) | undefined = undefined;
  confirmCellularDownload: (() => Promise<boolean>) | undefined = undefined;
  private loadToken: number = 0;

  // —— 音质状态（audio-quality-settings，随 emitUi 广播供页面 syncFrom 读取）——
  availableTracks: AudioTrack[] = [];      // 当前曲目 dash 可用音轨（durl/local 为空数组）
  currentQualityCode: number = 0;          // 实际生效 qn 码（30250/30251/30280/30232/30216；durl/local=0）
  currentTrackSource: string = '';         // 'dash' | 'durl'；未播放为 ''
  private currentCid: number = 0;          // 当前曲目 cid（切档零额外视频信息请求）
  // 最近一次取流请求档位：网络稳定切换目标档与之相同则跳过（避免无谓换流中断）
  private currentRequestedTier: QualityTier = QualityTier.MAX;
  // 当前网络是否 Wi-Fi（US6）：由 watchStableNetworkType 回调与 init 一次性查询共同维护
  private wifiNow: boolean = false;

  isWifiNow(): boolean {
    return this.wifiNow;
  }

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

  // 入队结果 → toast 文案（queue-redesign US6）：全库唯一映射点
  static enqueueToast(result: EnqueueResult): string {
    if (result === EnqueueResult.APPENDED) {
      return Constants.TOAST_ENQUEUE_APPENDED;
    }
    if (result === EnqueueResult.STARTED) {
      return Constants.TOAST_ENQUEUE_STARTED;
    }
    if (result === EnqueueResult.DUPLICATE) {
      return Constants.TOAST_ENQUEUE_DUPLICATE;
    }
    return Constants.TOAST_ENQUEUE_FAILED;
  }

  // 订阅 UI 刷新（US2/KI-1）：返回退订句柄，调用方须在 aboutToDisappear 中调用，
  // 避免页面销毁后监听器累积导致进度广播截断；owner 为调用方标识，用于生命周期日志追溯。
  // KI-5：非空 owner 采用单槽覆盖——同 owner 重复订阅时先移除旧监听器再压入新的。
  // 前提是 API 24 上 bindContentCover 内容组件可能收到伪 aboutToDisappear 导致漏退订，
  // 单槽覆盖保证即便如此，重复挂载也不会累积监听器。
  subscribe(fn: () => void, owner: string = ''): () => void {
    if (owner !== '') {
      for (let i = this.uiListeners.length - 1; i >= 0; i--) {
        if (this.uiListenerOwners[i] === owner) {
          this.uiListeners.splice(i, 1);
          this.uiListenerOwners.splice(i, 1);
        }
      }
      this.uiListeners.push(fn);
      this.uiListenerOwners.push(owner);
    } else if (this.uiListeners.indexOf(fn) < 0) {
      this.uiListeners.push(fn);
      this.uiListenerOwners.push('');
    }
    Logger.log('player', `subscribe${owner !== '' ? ` owner=${owner}` : ''}`,
      `listeners=${this.uiListeners.length}`);
    return (): void => {
      const idx: number = this.uiListeners.indexOf(fn);
      if (idx >= 0) {
        this.uiListeners.splice(idx, 1);
        this.uiListenerOwners.splice(idx, 1);
      }
      Logger.log('player', `unsubscribe${owner !== '' ? ` owner=${owner}` : ''}`,
        `listeners=${this.uiListeners.length}`);
    };
  }

  private emitUi(): void {
    for (let i = 0; i < this.uiListeners.length; i++) {
      try {
        this.uiListeners[i]();
      } catch (e) {
        // US2/KI-1：单监听器异常不得中断广播循环，其余监听器照常刷新
        const error = e as BusinessError;
        hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG,
          'emitUi listener error: %{public}s', error.message);
        Logger.log('player', 'emitUi listener error', error.message);
      }
    }
  }

  // 供 UI 层主动请求刷新（如设置开关切换后即时作用于封面/头像等渲染入口）
  refreshUi(): void {
    this.emitUi();
  }

  // US5：无图模式开关切换后对当前曲目重发系统播控元数据（force 绕过同曲目去重守卫），使封面显示即时更新
  refreshMediaSessionMetadata(): void {
    if (this.currentIndex < 0 || this.currentIndex >= this.playlist.length) {
      return;
    }
    const item: BiliVideo = this.playlist[this.currentIndex];
    const dataSaver: boolean = AppStore.getNumber(Constants.KEY_DATA_SAVER, 0) === 1;
    this.mediaSession.updateTrack(item.bvid, item.title,
      item.duration > 0 ? item.duration * 1000 : 0, dataSaver ? '' : item.cover, item.ownerName, true);
  }

  async init(): Promise<void> {
    if (this.inited) {
      return;
    }
    this.inited = true;
    try {
      await AppStore.init();

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

      // 音质档位存量迁移（audio-quality-settings FR-005）：-1 哨兵区分未初始化（迁移幂等）；
      // Wi-Fi 首次写入 MAX（最高），蜂窝按旧「优先低码率」开关映射 64K/132K，此后旧键不再读取
      if (AppStore.getNumber(Constants.KEY_WIFI_AUDIO_QUALITY, -1) < 0) {
        AppStore.putNumber(Constants.KEY_WIFI_AUDIO_QUALITY, QualityTier.MAX);
      }
      if (AppStore.getNumber(Constants.KEY_CELLULAR_AUDIO_QUALITY, -1) < 0) {
        const oldPreferLow: number = AppStore.getNumber(Constants.KEY_PREFER_LOW_BITRATE, 0);
        AppStore.putNumber(Constants.KEY_CELLULAR_AUDIO_QUALITY,
          oldPreferLow === 1 ? QualityTier.Q64K : QualityTier.Q132K);
      }

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

      // 网络稳定切换监听（audio-quality-settings FR-010）：进程生命周期内单例注册，
      // 网络在 Wi-Fi/流量间稳定切换后按新网络默认档自动换流（失败由 setQualityTier 回滚不打断）；
      // US6：回调同时维护 wifiNow 快照（isWifiNow 查询用），初值由一次性查询补齐
      NetUtil.isWifi().then((wifi: boolean): void => {
        this.wifiNow = wifi;
      }).catch((): void => {});
      NetUtil.watchStableNetworkType((isWifi: boolean): void => {
        this.wifiNow = isWifi;
        Logger.log('player', 'stable network change', `isWifi=${isWifi ? 1 : 0}`);
        // US6：网络态翻转广播 UI（播放页大封面按新档取图）
        this.emitUi();
        this.applyDefaultTierForNetwork().catch((): void => {});
      });
    } catch (e) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'init failed');
    }
    this.emitUi();
  }

  private onPlayerState(state: string): void {
    hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'player state: %{public}s, playWhenReady=%{public}d',
      state, this.playWhenReady ? 1 : 0);
    Logger.log('player', 'state', `${state} playWhenReady=${this.playWhenReady ? 1 : 0}`);
    if (state === 'prepared') {
      this.isPrepared = true;
      this.isPreparing = false;
      this.duration = this.player.duration;
      // US9：此前推送系统会话的时长为 0（条目未知时长）时，以真实时长 force 重推同曲目元数据，
      // 绕过 lastAssetId 去重，修复锁屏/控制中心进度条为空
      if (this.duration > 0 && this.currentIndex >= 0 && this.currentIndex < this.playlist.length) {
        const item: BiliVideo = this.playlist[this.currentIndex];
        if (item.duration <= 0) {
          const dataSaver: boolean = AppStore.getNumber(Constants.KEY_DATA_SAVER, 0) === 1;
          this.mediaSession.updateTrack(item.bvid, item.title, this.duration,
            dataSaver ? '' : item.cover, item.ownerName, true);
        }
      }
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
      // 完播标记（plan R5①）：自然播完 → 当前条目 progress=-1 即时写盘
      this.markCurrentHistoryCompleted();
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
    // 播完暂停（queue-redesign US3 FR-017）：自动切歌之前查询——命中则一次性解除（disarm）、
    // 标记播完、停在原条目；手动切歌/点选条目经 playIndex 清除 currentItemEnded 自然解除
    const st: SleepTimerController = SleepTimerController.getInstance();
    if (st.isPlayToEofActive()) {
      st.disarmPlayToEof();
      this.currentItemEnded = true;
      this.statusMsg = '本集播完已暂停';
      return;
    }
    if (this.pausedByUser) {
      this.statusMsg = '播放结束';
      this.currentItemEnded = true;
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
      this.currentItemEnded = true;
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
    // 完播阈值判定（plan R5②）：duration 已知且进度 ≥ duration×95% → 同样标记已听完
    // （覆盖「拖到结尾附近停住/切走」场景）；duration 未知（=0）保守不判定
    if (this.isPlaying && this.duration > 0 && time >= this.duration * Constants.PLAY_COMPLETE_RATIO) {
      this.markCurrentHistoryCompleted();
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
      // 全局断点（KEY_LAST_INDEX/KEY_LAST_POS_MS）写入路径零改动（不变式④，与每集进度互不干扰）
      AppStore.putNumber(Constants.KEY_LAST_INDEX, this.currentIndex);
      AppStore.putNumber(Constants.KEY_LAST_POS_MS, this.currentTime);
      // 每集进度（plan R6）：当前条目 progress=floor(currentTime/1000)（恒 ≥0，-1 仅由完播判定写入），
      // 随本 5s 节拍/暂停/切歌即时点异步写历史文件，异常退出进度回退 ≤ 一个节拍
      this.updateHistoryProgressForCurrent(Math.floor(this.currentTime / 1000));
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

  // 按当前网络类型读默认档（FR-002）：Wi-Fi→KEY_WIFI_AUDIO_QUALITY，否则→KEY_CELLULAR_AUDIO_QUALITY；
  // 存储值经 fromStored 归一（未初始化 -1 → MAX），供 playIndex 与自动换档复用
  private async readDefaultTierForNetwork(): Promise<QualityTier> {
    const isWifi: boolean = await NetUtil.isWifi();
    const key: string = isWifi ? Constants.KEY_WIFI_AUDIO_QUALITY : Constants.KEY_CELLULAR_AUDIO_QUALITY;
    return AudioQuality.fromStored(AppStore.getNumber(key, -1));
  }

  async loadPlaylistAndPlay(items: BiliVideo[], startIndex: number): Promise<EnqueueResult> {
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
        return EnqueueResult.STARTED;
      } else {
        this.statusMsg = '所选内容均已在歌单中';
        this.emitUi();
        return EnqueueResult.DUPLICATE;
      }
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
    return toAdd.length > 0 ? EnqueueResult.APPENDED : EnqueueResult.DUPLICATE;
  }

  // 续播起点查询（plan R4 契约）：条目存在且 progress>0 且 ≠-1 且（duration>0 时
  // progress < duration×PLAY_COMPLETE_RATIO）→ progress×1000；否则 0。纯查询，无副作用
  getResumeMsForBvid(bvid: string): number {
    for (let i = 0; i < this.playHistory.length; i++) {
      if (this.playHistory[i].bvid === bvid) {
        const entry: PlayHistoryItem = this.playHistory[i];
        if (entry.progress > 0 && entry.progress !== -1 &&
          (entry.duration <= 0 || entry.progress < entry.duration * Constants.PLAY_COMPLETE_RATIO)) {
          return entry.progress * 1000;
        }
        return 0;
      }
    }
    return 0;
  }

  async playIndex(index: number, seekMs: number, fromNav: boolean = false): Promise<void> {
    this.resumeAfterInterrupt = false;
    if (index < 0 || index >= this.playlist.length) {
      return;
    }
    // 每集进度（plan R4）：旧曲目仍在真实出声时先即时 flush 其进度（切歌写盘点）——
    // 此刻 currentIndex/currentTime/duration/currentCid 均属旧曲目，先落史再切换
    if (this.isPlaying && !this.isPreparing) {
      this.updateHistoryProgressForCurrent(Math.floor(this.currentTime / 1000));
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
    // US2：切剧入口初始化——重置秒级节流计数并取消挂起的 seekBy 防抖，
    // 杜绝上一集残留的广播状态导致新剧集进度条冻结
    this.lastEmittedSec = -1;
    if (this.seekByTimerId >= 0) {
      clearTimeout(this.seekByTimerId);
      this.seekByTimerId = -1;
      Logger.log('player', 'seekBy cancel', 'playIndex');
    }
    // 音质状态复位（audio-quality-settings）：切剧期间面板不残留上一首的音轨与档位
    this.availableTracks = [];
    this.currentQualityCode = 0;
    this.currentTrackSource = '';
    this.currentCid = 0;
    // 续播决策（plan R4）：仅新起播（seekMs<=0，如点历史条目/点单集入队/切歌）时以历史进度决定起点；
    // seekMs>0 的换音质保进度（setQualityTier resumePos）与全局断点恢复路径零变化
    let effectiveSeekMs: number = seekMs;
    if (seekMs <= 0) {
      effectiveSeekMs = this.getResumeMsForBvid(item.bvid);
      if (effectiveSeekMs > 0) {
        Logger.log('player', 'resume from history', `bvid=${item.bvid} ms=${effectiveSeekMs}`);
      }
    }
    Logger.log('player', 'playIndex', `index=${index} bvid=${item.bvid} seekMs=${seekMs} effective=${effectiveSeekMs}`);
    this.pendingSeekMs = effectiveSeekMs;
    this.currentTime = effectiveSeekMs;
    this.duration = item.duration > 0 ? item.duration * 1000 : 0;
    this.isPreparing = true;
    this.isPrepared = false;
    this.isPlaying = false;
    this.playWhenReady = true;
    this.pausedByUser = false;
    this.currentItemEnded = false;
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
      // 流式边下边播（US2）：现取直链（不持久化），缓冲态文案取代整段下载百分比；
      // 视频信息只拉一次——先回填元数据拿到 cid，再按网络默认档解析音轨（audio-quality-settings FR-002）
      this.statusMsg = '正在缓冲...';
      this.emitUi();
      const video: BiliVideo = await BiliService.fetchVideoInfo(item.bvid);
      if (token !== this.loadToken) {
        return;
      }
      this.applyTrackMeta(item, video);
      const tier: QualityTier = await this.readDefaultTierForNetwork();
      if (token !== this.loadToken) {
        return;
      }
      const result: ResolvedAudio = await BiliService.resolveAudioTrack(item.bvid, video.cid, tier);
      if (token !== this.loadToken) {
        return;
      }
      this.currentCid = video.cid;
      this.availableTracks = result.tracks;
      this.currentQualityCode = result.id;
      this.currentTrackSource = result.source;
      this.currentRequestedTier = tier;
      Logger.log('player', 'playIndex quality',
        `tier=${Number(tier)} qn=${result.id} source=${result.source} tracks=${result.tracks.length}`);
      this.emitUi();
      await this.openStreamWithRetry(result.urls);
      if (token !== this.loadToken) {
        return;
      }
      // US5：无图模式下系统播控不携带封面（空封面由 MediaSession 略过 mediaImage 字段，不传旧值）
      const dataSaver: boolean = AppStore.getNumber(Constants.KEY_DATA_SAVER, 0) === 1;
      this.mediaSession.updateTrack(item.bvid, item.title,
        item.duration > 0 ? item.duration * 1000 : 0, dataSaver ? '' : item.cover, item.ownerName);
      AppStore.savePlaylistFile(this.playlist, this.currentIndex, 0);
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
    // 播完暂停后手动续播：AVPlayer completed 态 play() 从头重播，同步复位播完标记与乐观进度
    if (this.currentItemEnded) {
      this.currentItemEnded = false;
      this.currentTime = 0;
    }
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
    this.currentItemEnded = false;
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
    this.currentItemEnded = false;
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
        Logger.log('player', 'seekBy fire', `target=${this.seekByTargetMs}`);
      } else {
        Logger.log('player', 'seekBy drop', 'not prepared');
      }
    }, Constants.SEEK_BY_DEBOUNCE_MS);
  }

  // 手动/自动换档（audio-quality-settings FR-004/FR-010）：换流保进度，复用 loadToken 并发模型
  // （并发切档以最后触发者为准）；writeBack=true（面板手动）按当前网络写回对应默认档键，
  // writeBack=false（网络自动换档）不写（目标档本就是新网络默认值）
  async setQualityTier(tier: QualityTier, writeBack: boolean): Promise<void> {
    if (this.currentTrackSource !== 'dash' || this.isPreparing || this.currentCid <= 0) {
      Logger.log('player', 'setQualityTier skip',
        `source=${this.currentTrackSource} preparing=${this.isPreparing ? 1 : 0} cid=${this.currentCid}`);
      return;
    }
    const item: BiliVideo | undefined = this.currentIndex >= 0 && this.currentIndex < this.playlist.length
      ? this.playlist[this.currentIndex] : undefined;
    if (item === undefined) {
      Logger.log('player', 'setQualityTier skip', 'no current item');
      return;
    }
    const resumePos: number = this.currentTime;
    const wasPlaying: boolean = this.isPlaying && !this.pausedByUser;
    const prevQualityCode: number = this.currentQualityCode;
    const prevStatusMsg: string = this.statusMsg;
    // 切档前取消挂起的 seekBy 防抖，防止其到期 seek 到已释放的旧实例
    if (this.seekByTimerId >= 0) {
      clearTimeout(this.seekByTimerId);
      this.seekByTimerId = -1;
      Logger.log('player', 'seekBy cancel', 'setQualityTier');
    }
    this.isPreparing = true;
    this.statusMsg = '正在切换音质…';
    this.emitUi();
    this.loadToken++;
    const token: number = this.loadToken;
    // prepared/playing 回调经既有 pendingSeekMs/playWhenReady 机制恢复进度与播放态
    this.pendingSeekMs = resumePos;
    this.currentTime = resumePos;
    this.playWhenReady = wasPlaying;
    Logger.log('player', 'setQualityTier',
      `bvid=${item.bvid} cid=${this.currentCid} tier=${Number(tier)} resumePos=${resumePos} wasPlaying=${wasPlaying ? 1 : 0}`);
    // 标记换流是否已进入重建阶段（旧实例已释放后失败须走恢复链）
    let streamBroken: boolean = false;
    try {
      const result: ResolvedAudio = await BiliService.resolveAudioTrack(item.bvid, this.currentCid, tier);
      if (token !== this.loadToken) {
        return;
      }
      streamBroken = true;
      await this.openStreamWithRetry(result.urls);
      if (token !== this.loadToken) {
        return;
      }
      this.currentQualityCode = result.id;
      this.availableTracks = result.tracks;
      this.currentTrackSource = result.source;
      this.currentRequestedTier = tier;
      if (writeBack) {
        const isWifi: boolean = await NetUtil.isWifi();
        const key: string = isWifi ? Constants.KEY_WIFI_AUDIO_QUALITY : Constants.KEY_CELLULAR_AUDIO_QUALITY;
        AppStore.putNumber(key, tier);
      }
      Logger.log('player', 'setQualityTier done',
        `qn=${result.id} source=${result.source} writeBack=${writeBack ? 1 : 0}`);
      this.emitUi();
      // 「已切换」提示延迟落定，避开 prepared/playing 事件对 statusMsg 的覆盖（此后由播放态自然清空）
      setTimeout((): void => {
        if (token !== this.loadToken) {
          return;
        }
        this.statusMsg = result.source === 'dash'
          ? `已切换 ${AudioQuality.trackLabel(result.id)}` : '已切换为默认流';
        this.emitUi();
      }, 600);
    } catch (err) {
      if (token !== this.loadToken) {
        return;
      }
      const error = err as BusinessError;
      Logger.log('player', 'setQualityTier failed', error.message);
      if (!streamBroken) {
        // 解析阶段失败：原流未动，直接回滚状态继续播放
        this.isPreparing = false;
        this.statusMsg = prevStatusMsg;
        this.emitUi();
        return;
      }
      // 换流阶段失败：原流已被重建释放，best-effort 以原档位重解析恢复（FR-010 失败保持原流不打断）
      this.statusMsg = '正在恢复播放...';
      this.emitUi();
      try {
        const backTier: QualityTier = AudioQuality.tierOfTrackId(prevQualityCode);
        const back: ResolvedAudio = await BiliService.resolveAudioTrack(item.bvid, this.currentCid, backTier);
        if (token !== this.loadToken) {
          return;
        }
        this.pendingSeekMs = resumePos;
        this.playWhenReady = wasPlaying;
        await this.openStreamWithRetry(back.urls);
        if (token !== this.loadToken) {
          return;
        }
        this.currentQualityCode = back.id;
        this.availableTracks = back.tracks;
        this.currentTrackSource = back.source;
        this.currentRequestedTier = backTier;
        this.statusMsg = back.source === 'dash'
          ? `音质切换失败，已恢复 ${AudioQuality.trackLabel(back.id)}` : '音质切换失败，已恢复默认流';
        Logger.log('player', 'quality restore ok', `qn=${back.id}`);
        this.emitUi();
      } catch (err2) {
        if (token !== this.loadToken) {
          return;
        }
        const error2 = err2 as BusinessError;
        this.isPreparing = false;
        this.statusMsg = `切换音质失败: ${error2.message}`;
        Logger.log('player', 'quality restore failed', error2.message);
        this.emitUi();
      }
    }
  }

  // 网络稳定切换自动换档（FR-010）：仅在线 dash 流且非切剧中触发；
  // 目标档与最近取流档相同则跳过（避免无谓换流中断），失败由 setQualityTier 回滚保持原流
  private async applyDefaultTierForNetwork(): Promise<void> {
    if (this.currentTrackSource !== 'dash' || this.isPreparing || this.currentCid <= 0) {
      Logger.log('player', 'auto tier switch skip',
        `source=${this.currentTrackSource} preparing=${this.isPreparing ? 1 : 0}`);
      return;
    }
    const tier: QualityTier = await this.readDefaultTierForNetwork();
    if (tier === this.currentRequestedTier) {
      Logger.log('player', 'auto tier switch skip', 'same tier');
      return;
    }
    Logger.log('player', 'auto tier switch', `tier=${Number(tier)}`);
    await this.setQualityTier(tier, false);
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

  // 单视频入队统一入口（queue-redesign US6）：取详情后委托 loadPlaylistAndPlay——
  // 队列空则起播（STARTED），非空则追加不打断（APPENDED），重复返回 DUPLICATE
  async addSingleVideo(bvid: string): Promise<EnqueueResult> {
    const trimmed: string = bvid.trim();
    if (trimmed === '') {
      this.statusMsg = '请输入BV号';
      this.emitUi();
      return EnqueueResult.FAILED;
    }
    this.statusMsg = '正在解析...';
    this.emitUi();
    try {
      const video: BiliVideo = await BiliService.fetchVideoInfo(trimmed);
      return await this.loadPlaylistAndPlay([video], 0);
    } catch (err) {
      const error = err as BusinessError;
      this.statusMsg = `解析失败: ${error.message}`;
      this.emitUi();
      return EnqueueResult.FAILED;
    }
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
    this.playlist.splice(this.currentIndex, 1);
    this.playlistVersion++;
    if (this.playlist.length === 0) {
      this.currentIndex = -1;
      this.isPrepared = false;
      this.isPlaying = false;
      this.currentItemEnded = false;
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

  private resolveSourceType(video: BiliVideo): number {
    if (video.folderIds.length > 0) {
      return PlayHistoryItem.SOURCE_FAVORITE;
    }
    if (video.seasonKeys.length > 0) {
      return PlayHistoryItem.SOURCE_SEASON;
    }
    return PlayHistoryItem.SOURCE_LOCAL;
  }

  // 按历史条目主键检索（bvid 全局至多一条，upsert 保证）
  private indexOfPlayHistory(bvid: string): number {
    for (let i = 0; i < this.playHistory.length; i++) {
      if (this.playHistory[i].bvid === bvid) {
        return i;
      }
    }
    return -1;
  }

  // 历史文件异步写盘：沿用既有 setTimeout(0) 模式，进度节拍/切歌/完播/删除共用，不阻塞调用线程
  private savePlayHistoryFileAsync(): void {
    setTimeout((): void => {
      try {
        AppStore.savePlayHistoryFile(this.playHistory);
      } catch (e) {
        hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'savePlayHistoryFile failed');
      }
    }, 0);
  }

  // 条目元数据回填（plan R7）：duration 取播放器真实时长（this.duration 毫秒→秒，含 BiliVideo.duration
  // 冷启动兜底已先经 upsert 写入）；cid 取 currentCid（流式路径）或队列条目 cid 中非零者。
  // 调用时机（this.currentIndex/currentCid/duration 与目标条目一致）保证回填不串曲目
  private backfillHistoryMeta(entry: PlayHistoryItem): void {
    if (this.duration > 0) {
      const durationSec: number = Math.floor(this.duration / 1000);
      if (durationSec > 0) {
        entry.duration = durationSec;
      }
    }
    let cid: number = this.currentCid;
    if (cid <= 0 && this.currentIndex >= 0 && this.currentIndex < this.playlist.length) {
      cid = this.playlist[this.currentIndex].cid;
    }
    if (cid > 0) {
      entry.cid = cid;
    }
  }

  // 更新当前条目进度（plan R6，persistProgress/切歌 flush 共用）：
  // 仅命中已有条目才更新（未记录过的条目等 playing 状态 upsert 创建）；
  // progress===-1（已完播）不回写正数进度，保住完播标记（不变式①）
  private updateHistoryProgressForCurrent(progressSec: number): void {
    if (this.currentIndex < 0 || this.currentIndex >= this.playlist.length) {
      return;
    }
    const bvid: string = this.playlist[this.currentIndex].bvid;
    if (bvid === '') {
      return;
    }
    const idx: number = this.indexOfPlayHistory(bvid);
    if (idx < 0) {
      return;
    }
    const entry: PlayHistoryItem = this.playHistory[idx];
    this.backfillHistoryMeta(entry);
    if (entry.progress !== -1 && entry.progress !== progressSec) {
      entry.progress = progressSec;
      this.playHistoryVersion++;
    }
    this.savePlayHistoryFileAsync();
  }

  // 完播标记（plan R5）：当前条目 progress=-1 即时写盘（对齐 B 站「-1=看完」语义）；
  // 已是 -1 则幂等跳过（含跳过写盘），避免播放 tick 高频重复落盘
  private markCurrentHistoryCompleted(): void {
    if (this.currentIndex < 0 || this.currentIndex >= this.playlist.length) {
      return;
    }
    const bvid: string = this.playlist[this.currentIndex].bvid;
    const idx: number = this.indexOfPlayHistory(bvid);
    if (idx < 0) {
      return;
    }
    const entry: PlayHistoryItem = this.playHistory[idx];
    if (entry.progress === -1) {
      return;
    }
    this.backfillHistoryMeta(entry);
    entry.progress = -1;
    this.playHistoryVersion++;
    Logger.log('player', 'history complete', `bvid=${bvid}`);
    this.savePlayHistoryFileAsync();
  }

  // 播放历史 upsert（plan R3，play-history-progress 最关键修正）：
  // 命中同 bvid 旧条目时**保留** progress/duration/cid（续播进度不被清零），仅刷新
  // viewAt(秒)/title/cover/ownerName/sourceType 后置顶；未命中才新建（progress=0）。
  // 重播已听完条目时 -1 → 0（不变式①：-1 仅由完播写入，重播 upsert 重置）。
  // 仍仅在 playing 状态（AVPlayer 真实出声）触发
  private recordOnPlaying(video: BiliVideo): void {
    try {
      let existing: PlayHistoryItem | undefined = undefined;
      for (let i = this.playHistory.length - 1; i >= 0; i--) {
        if (this.playHistory[i].bvid === video.bvid) {
          if (existing === undefined) {
            existing = this.playHistory[i];
          }
          this.playHistory.splice(i, 1);
        }
      }
      let item: PlayHistoryItem;
      if (existing !== undefined) {
        existing.title = video.title;
        existing.ownerName = video.ownerName;
        existing.cover = video.cover;
        existing.sourceType = this.resolveSourceType(video);
        existing.viewAt = Math.floor(Date.now() / 1000);
        if (video.cid > 0) {
          existing.cid = video.cid;
        }
        if (video.duration > 0) {
          existing.duration = video.duration;
        }
        if (existing.progress === -1) {
          existing.progress = 0;
        }
        item = existing;
      } else {
        item = PlayHistoryItem.fromVideo(video, this.resolveSourceType(video), Date.now());
      }
      this.playHistory.unshift(item);
      if (this.playHistory.length > Constants.HISTORY_MAX) {
        this.playHistory = this.playHistory.slice(0, Constants.HISTORY_MAX);
      }
      this.playHistoryVersion++;
      hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG,
        'recordOnPlaying upsert bvid=%{public}s source=%{public}d progress=%{public}d total=%{public}d',
        item.bvid, item.sourceType, item.progress, this.playHistory.length);
      this.savePlayHistoryFileAsync();
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

  // 单条删除（US3 FR-009）：按 bvid 移除一条历史，异步写盘；未命中静默。
  // 面板条目自带左滑刷新，不在此处 emitUi（FR-014：clearPlayHistory 行为保持不变）
  removePlayHistoryItem(bvid: string): void {
    const idx: number = this.indexOfPlayHistory(bvid);
    if (idx < 0) {
      return;
    }
    this.playHistory.splice(idx, 1);
    this.playHistoryVersion++;
    Logger.log('player', 'history remove', `bvid=${bvid} left=${this.playHistory.length}`);
    this.savePlayHistoryFileAsync();
  }

  async removeSelectedFromPlaylist(bvids: string[]): Promise<void> {    if (bvids.length === 0) {
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
      this.currentItemEnded = false;
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

  // 清除已播（queue-redesign US4 FR-009/FR-010）：移除 [0, currentIndex) 前缀；
  // currentItemEnded 时连当前条目一并移除——播完态清除后无当前条目（currentIndex=-1、
  // isPrepared/isPlaying=false、resetPlayer、持久化 (playlist, -1, 0)，队列空同此语义）；
  // 播放中仅移前缀、索引前移到 0、不打断播放；无可清（无前缀且未播完）静默返回。
  // UI 侧经 playlistVersion++ 触发 syncFrom 的 diff 增量刷新（notifyDataDelete 从高到低）
  async clearPlayedItems(): Promise<void> {
    const ci: number = this.currentIndex;
    const ended: boolean = this.currentItemEnded && ci >= 0 && ci < this.playlist.length;
    const prefix: number = ci > 0 ? ci : 0;
    if (prefix === 0 && !ended) {
      return;
    }
    const keepFrom: number = ended ? ci + 1 : ci;
    const kept: BiliVideo[] = this.playlist.slice(keepFrom);
    this.playlist = kept;
    this.playlistVersion++;
    this.currentItemEnded = false;
    if (!ended) {
      this.currentIndex = 0;
      this.statusMsg = '已清除已播条目';
      AppStore.savePlaylistFile(this.playlist, 0, this.currentTime);
    } else {
      this.currentIndex = -1;
      this.isPrepared = false;
      this.isPlaying = false;
      this.currentTime = 0;
      this.duration = 0;
      await this.player.resetPlayer();
      this.statusMsg = '已清除已播条目';
      AppStore.savePlaylistFile(this.playlist, -1, 0);
    }
    this.emitUi();
  }
}
