// 全库唯一常量定义点：日志、存储名、持久化键、AppStorage 键、魔法数字与受限色值均在此集中。
// 该模块仅依赖 ArkTS 内建类型，不 import 任何业务模块，避免循环依赖。
// 注意：应用级标识（LOG_TAG/STORE_NAME/SECURE_STORE_NAME/AS_GRIP_ON_RIGHT）自 BiliRadio 1.0.0 起启用新键名
// （BiliRadio 为全新独立应用，独立 bundleName/沙箱，不涉及旧数据迁移）；其余持久化键与 AppStorage 键取值
// 与上游逐字一致，收敛仅改变引用方式。
//
// 单例范式约束：后续新增服务类若需单例，必须复用
//   private static instance: X | undefined = undefined;
//   static getInstance(): X { ... }
// 的一致写法，禁止引入第三种单例写法（现状 PlayerController/BiliSession/MediaSession/DownloadManager 四处已一致，不引入抽象基类）。

export class Constants {
  // —— 日志 ——
  static readonly LOG_DOMAIN: number = 0x0200;
  static readonly LOG_TAG: string = 'BiliRadio';

  // —— 存储名 ——
  static readonly STORE_NAME: string = 'biliradio_store';
  static readonly SECURE_STORE_NAME: string = 'biliradio_secure';
  static readonly SECURE_PREFIX: string = 'secure_';

  // —— Cookie/Asset 别名 ——
  static readonly COOKIE_ALIAS: string = 'bili_cookie';

  // —— Preferences 持久化键 ——
  static readonly KEY_PLAY_MODE: string = 'playMode';
  static readonly KEY_PLAYBACK_RATE: string = 'playbackRate';
  static readonly KEY_LAST_INDEX: string = 'lastIndex';
  static readonly KEY_LAST_POS_MS: string = 'lastPosMs';
  static readonly KEY_AUTO_PLAY_ON_START: string = 'autoPlayOnStart';
  static readonly KEY_SELECTED_FOLDER_IDS: string = 'selectedFolderIds';
  static readonly KEY_SELECTED_SEASONS: string = 'selectedSeasons';
  static readonly KEY_LAST_SEASON_MID: string = 'lastSeasonMid';
  static readonly KEY_SYNC_BLOCKED_UNTIL: string = 'syncBlockedUntil';
  static readonly KEY_SYNC_FOLDER_COUNTS: string = 'syncFolderCounts';
  static readonly KEY_COLOR_MODE: string = 'colorMode';
  static readonly KEY_INTERRUPT_RESUME: string = 'interruptResume';
  static readonly KEY_DATA_SAVER: string = 'dataSaver';
  static readonly KEY_PREFER_LOW_BITRATE: string = 'preferLowBitrate';
  static readonly KEY_WIFI_ONLY_DOWNLOAD: string = 'wifiOnlyDownload';
  static readonly KEY_CO_PLAY_WITH_OTHERS: string = 'coPlayWithOthers';
  static readonly PLAY_HISTORY_FILE: string = 'play_history.json';

  // —— AppStorage 键 ——
  static readonly AS_COLOR_MODE_SETTING: string = 'colorModeSetting';
  static readonly AS_COLOR_MODE_RESOLVED: string = 'colorModeResolved';
  static readonly AS_COVER_BRIGHTNESS: string = 'coverBrightness';
  static readonly AS_COVER_IS_DARK: string = 'coverIsDark';
  static readonly AS_STATUS_BAR_HEIGHT: string = 'statusBarHeight';
  static readonly AS_NAV_BAR_HEIGHT: string = 'navBarHeight';
  static readonly AS_FLOATING_TAB_HEIGHT: string = 'floatingTabHeight';
  static readonly AS_GRIP_ON_RIGHT: string = 'biliRadioGripOnRight';
  static readonly AS_IS_WIDE_SCREEN: string = 'isWideScreen';

  // —— AppStorage 瞬态 UI 键（弹层/多选等运行时状态，不持久化） ——
  static readonly AS_SHOW_HISTORY: string = 'showHistory';
  static readonly AS_SHOW_SPEED: string = 'showSpeed';
  static readonly AS_SHOW_MODE: string = 'showMode';
  static readonly AS_PLAYLIST_SELECT_MODE: string = 'playlistSelectMode';
  static readonly AS_FOLDER_SELECT_MODE: string = 'folderSelectMode';
  static readonly AS_FOLDER_DOWNLOAD_SELECT_MODE: string = 'folderDownloadSelectMode';
  static readonly AS_SHOW_SLEEP_TIMER: string = 'showSleepTimer';
  static readonly AS_SHOW_SLEEP_TIMER_PICKER: string = 'showSleepTimerPicker';
  static readonly AS_SHOW_SEARCH: string = 'showSearch';
  static readonly AS_SHOW_PLAY_HISTORY: string = 'showPlayHistory';
  static readonly AS_SHOW_PLAYER_OVERLAY: string = 'showPlayerOverlay';
  static readonly AS_SHOW_QUEUE_SHEET: string = 'showQueueSheet';

  // —— 受限色值（窗口层 API / Canvas 2D 不接受颜色资源引用，只能写字面量） ——
  // 仅能在此唯一定义，禁止其他文件重复声明
  static readonly QR_FG_COLOR: string = '#000000';
  static readonly QR_BG_COLOR: string = '#FFFFFF';
  static readonly WIN_BG_DARK: string = '#121214';
  static readonly WIN_BG_LIGHT: string = '#F6F6FA';
  static readonly BAR_CONTENT_DARK: string = '#FFFFFF';
  static readonly BAR_CONTENT_LIGHT: string = '#1A1A1A';
  static readonly PROBE_DARK_RGB: number = 0x121214;

  // —— 主题色（accent）：预设色板，深浅两态下均已校验对比度；仅接受色板内取值 ——
  static readonly KEY_ACCENT_COLOR: string = 'accentColor';
  static readonly AS_ACCENT_COLOR: string = 'accentColor';
  static readonly ACCENT_DEFAULT: string = '#FB7299';
  static readonly ACCENT_PRESETS: string[] =
    ['#FB7299', '#4C8DFF', '#9C6BFF', '#2EC8B4', '#FF9F43', '#5FBF6B'];

  // —— 魔法数字 ——
  static readonly HISTORY_MAX: number = 200;
  static readonly SEARCH_MAX_INPUT_LEN: number = 50;
  static readonly PROGRESS_SAVE_INTERVAL_MS: number = 5000;
  static readonly PREV_SEEK_THRESHOLD_MS: number = 3000;
  static readonly BYTES_PER_MB: number = 1048576;
  static readonly MAX_CACHE_BYTES: number = 600 * 1024 * 1024;
  static readonly TARGET_CACHE_BYTES: number = 400 * 1024 * 1024;
  static readonly CONNECT_TIMEOUT_MS: number = 15000;
  static readonly READ_TIMEOUT_MS: number = 30000;
  static readonly STREAM_TIMEOUT_MS: number = 120000;
  static readonly COVER_DARK_THRESHOLD: number = 128;
  static readonly FLOATING_TAB_HEIGHT: number = 90;
  static readonly COVER_BRIGHTNESS_DARK: number = 0.8;
  static readonly COVER_BRIGHTNESS_LIGHT: number = 1.0;
  static readonly SLEEP_TIMER_PRESETS: number[] = [15 * 60, 30 * 60, 60 * 60];
  static readonly SLEEP_TIMER_MAX_HOURS: number = 12;
  static readonly SLEEP_TIMER_MIN_SECONDS: number = 60;
  static readonly SLEEP_TIMER_TICK_MS: number = 1000;
}

// 延时工具：全库唯一实现，供各处「等待固定时长」复用。
export function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout(() => { resolve(); }, ms);
  });
}