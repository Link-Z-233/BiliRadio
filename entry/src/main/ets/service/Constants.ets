// 全库唯一常量定义点：日志、存储名、持久化键、AppStorage 键、魔法数字与受限色值均在此集中。
// 该模块仅依赖 ArkTS 内建类型，不 import 任何业务模块，避免循环依赖。
// 注意：应用级标识（LOG_TAG/STORE_NAME/SECURE_STORE_NAME/AS_GRIP_ON_RIGHT）自 BiliRadio 1.0.0 起启用新键名
// （BiliRadio 为全新独立应用，独立 bundleName/沙箱，不涉及旧数据迁移）；其余持久化键与 AppStorage 键取值
// 与上游逐字一致，收敛仅改变引用方式。
//
// 单例范式约束：后续新增服务类若需单例，必须复用
//   private static instance: X | undefined = undefined;
//   static getInstance(): X { ... }
// 的一致写法，禁止引入第三种单例写法（现状 PlayerController/BiliSession/MediaSession 三处已一致，不引入抽象基类）。

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
  static readonly KEY_COLOR_MODE: string = 'colorMode';
  static readonly KEY_INTERRUPT_RESUME: string = 'interruptResume';
  // 仅供存量迁移读取，链路已退役（audio-quality-settings）
  static readonly KEY_PREFER_LOW_BITRATE: string = 'preferLowBitrate';
  static readonly KEY_WIFI_ONLY_DOWNLOAD: string = 'wifiOnlyDownload';
  // 音质档位键（audio-quality-settings）：存 QualityTier 值；-1 = 未初始化（迁移哨兵）
  static readonly KEY_WIFI_AUDIO_QUALITY: string = 'wifiAudioQuality';
  static readonly KEY_CELLULAR_AUDIO_QUALITY: string = 'cellularAudioQuality';
  static readonly KEY_DEBUG_MODE: string = 'debugMode';
  static readonly PLAY_HISTORY_FILE: string = 'play_history.json';

  // —— AppStorage 键 ——
  static readonly AS_COLOR_MODE_SETTING: string = 'colorModeSetting';
  static readonly AS_COLOR_MODE_RESOLVED: string = 'colorModeResolved';
  static readonly AS_STATUS_BAR_HEIGHT: string = 'statusBarHeight';
  static readonly AS_NAV_BAR_HEIGHT: string = 'navBarHeight';
  static readonly AS_GRIP_ON_RIGHT: string = 'biliRadioGripOnRight';
  static readonly AS_IS_WIDE_SCREEN: string = 'isWideScreen';

  // —— AppStorage 瞬态 UI 键（弹层/多选等运行时状态，不持久化） ——
  static readonly AS_SHOW_SPEED: string = 'showSpeed';
  static readonly AS_SHOW_MODE: string = 'showMode';
  static readonly AS_PLAYLIST_SELECT_MODE: string = 'playlistSelectMode';
  static readonly AS_SHOW_SLEEP_TIMER: string = 'showSleepTimer';
  static readonly AS_SHOW_SLEEP_TIMER_PICKER: string = 'showSleepTimerPicker';
  static readonly AS_SHOW_PLAY_HISTORY: string = 'showPlayHistory';
  static readonly AS_SHOW_PLAYER_OVERLAY: string = 'showPlayerOverlay';
  static readonly AS_SHOW_QUEUE_SHEET: string = 'showQueueSheet';
  static readonly AS_MINI_PLAYER_VISIBLE: string = 'miniPlayerVisible';
  static readonly AS_ON_SETTINGS_PAGE: string = 'onSettingsPage';
  static readonly AS_HOME_REFRESH_TICK: string = 'homeRefreshTick';

  // —— 受限色值（窗口层 API / Canvas 2D 不接受颜色资源引用，只能写字面量） ——
  // 仅能在此唯一定义，禁止其他文件重复声明
  static readonly QR_FG_COLOR: string = '#000000';
  static readonly QR_BG_COLOR: string = '#FFFFFF';
  static readonly WIN_BG_DARK: string = '#121214';
  static readonly WIN_BG_LIGHT: string = '#F6F6FA';
  static readonly BAR_CONTENT_DARK: string = '#FFFFFF';
  static readonly BAR_CONTENT_LIGHT: string = '#1A1A1A';

  // —— 主题色（accent）：预设色板，深浅两态下均已校验对比度；仅接受色板内取值 ——
  static readonly KEY_ACCENT_COLOR: string = 'accentColor';
  static readonly AS_ACCENT_COLOR: string = 'accentColor';
  static readonly ACCENT_DEFAULT: string = '#FB7299';
  static readonly ACCENT_PRESETS: string[] =
    ['#FB7299', '#4C8DFF', '#9C6BFF', '#2EC8B4', '#FF9F43', '#5FBF6B'];

  // —— 魔法数字 ——
  static readonly HISTORY_MAX: number = 200;
  static readonly PROGRESS_SAVE_INTERVAL_MS: number = 5000;
  // 完播阈值（play-history-progress FR-003/FR-004）：进度 ≥ 时长×该比例视为已听完（progress=-1），不暴露为设置
  static readonly PLAY_COMPLETE_RATIO: number = 0.95;
  static readonly PREV_SEEK_THRESHOLD_MS: number = 3000;
  static readonly CONNECT_TIMEOUT_MS: number = 15000;
  static readonly READ_TIMEOUT_MS: number = 30000;
  // 短链解析专用超时（bili-link-recognize / KI-4 修复）：302 响应体实测 ≤1KB，8s 覆盖弱网单跳往返且短于通用值
  static readonly SHORT_LINK_CONNECT_MS: number = 8000;
  static readonly SHORT_LINK_READ_MS: number = 8000;
  static readonly STREAM_TIMEOUT_MS: number = 120000;
  static readonly SLEEP_TIMER_PRESETS: number[] = [15 * 60, 30 * 60, 60 * 60];
  static readonly SLEEP_TIMER_MAX_HOURS: number = 12;
  static readonly SLEEP_TIMER_MIN_SECONDS: number = 60;
  static readonly SLEEP_TIMER_TICK_MS: number = 1000;
  // 悬浮播放胶囊占位高度：胶囊高约 60 + 底部 8 偏移 + 余量，供各滚动页底部预留
  static readonly MINI_PLAYER_CLEARANCE: number = 88;
  static readonly DEBUG_TAP_WINDOW_MS: number = 2000;

  // —— 播放微调与防抖（自 PlayerOverlay/PlayerController 迁入；播放页按钮与播控中心快进快退共用同一来源） ——
  // ±15s 进度微调步长（ms）：固定 15 秒，不可配置（spec FR-013）
  static readonly SEEK_STEP_MS: number = 15000;
  // seekBy 连按合并防抖窗口（ms）：防抖期内的新调用基于最新进度叠加，到期仅执行最终一次 player.seek
  static readonly SEEK_BY_DEBOUNCE_MS: number = 250;
  // 应用内日志环形缓冲上限（条）：超限淘汰最旧（US9）
  static readonly LOG_BUFFER_MAX: number = 500;
  // 日志落盘文件名（US9）：位于应用沙箱 filesDir，单行可读格式追加写入
  static readonly LOG_FILE_NAME: string = 'biliradio_log.txt';
  // 日志落盘硬上限（字节）：超限保留最新一半重写（滚动淘汰），文件占用有界
  static readonly LOG_FILE_MAX_BYTES: number = 512 * 1024;

  // —— 删除补位动画与面板关闭时序（v0.3-bugfix-round2 US6/US8）——
  // 删除数据变更包 animateTo 的过渡时长（ms）：notifyDataDelete 落闭包内即补位动画
  static readonly TOKEN_DELETE_ANIM_MS: number = 250;
  // 队列面板滑出动画结束后卸载/关浮层的延时（ms）：略长于 250ms 滑出动画保证完整播完
  static readonly DRAWER_CLOSE_DELAY_MS: number = 260;
  // 清空队列延时清数据（ms，v0.3-bugfix-round3 US4）：先关层后清数据，延时大于浮层 350ms 转场保证清数据时浮层已卸载
  static readonly CLEAR_QUEUE_DATA_DELAY_MS: number = 400;
  // 设置页退场转场定值延时（v0.3-bugfix-round4 US2）：ponytail: 系统导航退场转场无公开完成回调，定值略长于默认转场，胶囊上浮始于转场结束后
  static readonly NAV_EXIT_TRANSITION_MS: number = 400;

  // —— 左滑删除圆钮（v0.3-bugfix-round3 US6）：圆形红底垃圾桶，尺寸/圆角/图标字号唯一来源 ——
  static readonly SWIPE_DELETE_BTN_SIZE: number = 44;
  static readonly SWIPE_DELETE_BTN_RADIUS: number = 22;
  static readonly SWIPE_DELETE_ICON_FONT: number = 18;

  // —— B 站端点与 UA（US3：未登录查询 UP 投稿风控修复） ——
  // APP 投稿端点：BiliDroid 客户端渠道，无需 cookie/WBI 即可查询投稿列表
  static readonly BILI_APP_ARCHIVE_URL: string = 'https://app.bilibili.com/x/v2/space/archive/cursor';
  static readonly TV_APP_KEY: string = 'dfca71928277209b';
  static readonly TV_APP_SEC: string = 'b5475a8825547a4fc26c7d518eaaa02e';
  // ExClimbWuzhi 风控网关：buvid 激活（PiliPlus 同源路径）
  static readonly BILI_EXCLIMB_WUZHI_URL: string = 'https://api.bilibili.com/x/internal/gaia-gateway/ExClimbWuzhi';
  // BiliDroid 客户端 UA（与 PiliPlus constants.dart 同源）：APP 端点与 ExClimbWuzhi 激活共用
  static readonly BILI_APP_USER_AGENT: string =
    'Mozilla/5.0 BiliDroid/8.43.0 (bbcallen@gmail.com) os/android model/android mobi_app/android build/8430300 channel/master innerVer/8430300 osVer/15 network/2';

  // —— 播放按钮尺寸同源（US1/US4）：按钮直径为唯一尺寸源，缓冲加载指示尺寸由此派生，调整不再脱节 ——
  static readonly PLAY_BTN_DIAMETER: number = 80;   // 播放按钮直径

  // —— 加载更多失败冷却（US2）：失败后冷却期内禁用重试，防止弱网下反复请求 ——
  static readonly LOAD_OLDER_FAIL_COOLDOWN_MS: number = 3000;

  // —— 订阅翻页页大小（KI-9 页界统一）：APP 签名链服务端钳 20，Web 链与记账统一对齐 ——
  static readonly UP_PAGE_SIZE: number = 20;
  static readonly SEASON_PAGE_SIZE: number = 20;
  static readonly FAV_PAGE_SIZE: number = 20;

  // —— 队列入队反馈（queue-redesign US6）：三分型 toast 文案 ——
  static readonly TOAST_ENQUEUE_APPENDED: string = '已加入队列';
  static readonly TOAST_ENQUEUE_STARTED: string = '开始播放';
  static readonly TOAST_ENQUEUE_DUPLICATE: string = '已在队列中';
  static readonly TOAST_ENQUEUE_FAILED: string = '添加失败';
  // —— 清除已播（queue-redesign US4）：无可清 toast 与二次确认框文案 ——
  static readonly TOAST_QUEUE_NO_PLAYED: string = '没有可清除的已播内容';
  static readonly DIALOG_CLEAR_PLAYED_TITLE: string = '清除已播';
  // v0.3-bugfix-round2 US3：计数式文案（N 由实际可清条目数代入）
  static readonly DIALOG_CLEAR_PLAYED_COUNT_MSG: string = '确定清除 N 首已播条目吗？';
  // —— 删除二次确认（v0.3-bugfix-round2 US1/US2）：三处左滑 + 多选移除 ——
  static readonly DIALOG_DELETE_HISTORY_TITLE: string = '删除播放记录';
  static readonly DIALOG_DELETE_HISTORY_MSG: string = '确定删除这条播放记录吗？';
  static readonly DIALOG_DELETE_QUEUE_ITEM_TITLE: string = '移除队列条目';
  static readonly DIALOG_DELETE_QUEUE_ITEM_MSG: string = '确定从队列移除该条目吗？';
  static readonly DIALOG_DELETE_SUB_TITLE: string = '删除订阅';
  static readonly DIALOG_DELETE_SUB_MSG: string = '确定删除该订阅吗？';
  static readonly DIALOG_REMOVE_SELECTED_TITLE: string = '移除所选';
  static readonly DIALOG_REMOVE_SELECTED_MSG: string = '确定移除所选条目吗？';
  // —— 队列空态引导（queue-redesign US1） ——
  static readonly QUEUE_EMPTY_HINT: string = '到订阅源详情页播放节目，或在首页点「＋」添加订阅';

  // —— 播放页封面取色（palette-glow/palette-bg）：取色与背景衍生色参数唯一来源 ——
  // 取色缓存上限（条）：满则整体清空重新积累
  static readonly PALETTE_CACHE_MAX: number = 24;
  // 取色解码目标尺寸（px）：仅供 ColorPicker 采样，小图足够
  static readonly PALETTE_DECODE_W: number = 48;
  static readonly PALETTE_DECODE_H: number = 32;
  // 取色封面拉取档：与列表缩略图同档（颜色采样无需大图）
  static readonly PALETTE_FETCH_W: number = 240;
  static readonly PALETTE_FETCH_H: number = 240;
  // 主色择优阈值：占比色 RGB 通道极差低于该值视为灰（黑/白/灰底封面），改取最高饱和色
  static readonly PALETTE_GRAY_SPREAD: number = 24;
  // 占比色感知亮度低于该值视为过暗（黑边/暗部主导），改取最高饱和色
  static readonly PALETTE_DARK_LUMA: number = 50;
  // 播放页封面上边距（vp）：US10 基础上下移，给光晕上方留渲染空间（US5 顶栏截断缓解）
  static readonly COVER_TOP_GAP: number = 40;
  // 背景衍生色饱和度区间（0-1）：压至该区间保证柔和不抢眼
  static readonly PALETTE_BG_SAT_MIN: number = 0.10;
  static readonly PALETTE_BG_SAT_MAX: number = 0.20;
  // 背景衍生色明度目标（0-1）：浅色外观近白 / 深色外观近黑
  static readonly PALETTE_BG_L_LIGHT: number = 0.91;
  static readonly PALETTE_BG_L_DARK: number = 0.11;
  // 光晕基色深色外观明度目标（0-1）：保留色相/饱和度、压至暗调氛围光（纯灰白取色回退主题色见 glowTint）
  static readonly PALETTE_GLOW_L_DARK: number = 0.25;
  // 背景渐变首取色淡入时长（ms）
  static readonly PALETTE_BG_REVEAL_MS: number = 500;

  // —— 封面尺寸档位（US6）：列表缩略图/播放页大封面/播控中心降档，尺寸只需在此调整 ——
  static readonly COVER_THUMB_W: number = 240;
  static readonly COVER_THUMB_H: number = 240;
  static readonly COVER_BIG_W: number = 672;
  static readonly COVER_BIG_H: number = 378;
  static readonly COVER_SAVER_W: number = 480;
  static readonly COVER_SAVER_H: number = 270;

  // —— UI 令牌档位（US2，plan.md R2）：数值不变仅统一来源，观感收敛列远期 ——
  // 字号：基础档（plan）+ 实测扩展档（数值后缀命名）
  static readonly TOKEN_FONT_CAPTION: number = 10;
  static readonly TOKEN_FONT_AUX: number = 11;
  static readonly TOKEN_FONT_BODY_S: number = 12;
  static readonly TOKEN_FONT_BODY: number = 13;
  static readonly TOKEN_FONT_BODY_M: number = 14;
  static readonly TOKEN_FONT_BODY_L: number = 15;
  static readonly TOKEN_FONT_TITLE: number = 16;
  static readonly TOKEN_FONT_18: number = 18;
  static readonly TOKEN_FONT_20: number = 20;
  static readonly TOKEN_FONT_TITLE_L: number = 22;
  static readonly TOKEN_FONT_24: number = 24;
  static readonly TOKEN_FONT_56: number = 56;
  // 圆角：基础档（plan）+ 实测扩展档
  static readonly TOKEN_RADIUS_S: number = 8;
  static readonly TOKEN_RADIUS_M: number = 12;
  static readonly TOKEN_RADIUS_L: number = 16;
  static readonly TOKEN_RADIUS_XL: number = 20;
  static readonly TOKEN_RADIUS_XXL: number = 24;
  static readonly TOKEN_RADIUS_10: number = 10;
  static readonly TOKEN_RADIUS_14: number = 14;
  static readonly TOKEN_RADIUS_18: number = 18;
  static readonly TOKEN_RADIUS_22: number = 22;
  // 间距：基础档（plan）+ 实测扩展档
  static readonly TOKEN_SPACE_XXS: number = 2;
  static readonly TOKEN_SPACE_XS: number = 4;
  static readonly TOKEN_SPACE_S: number = 8;
  static readonly TOKEN_SPACE_M: number = 12;
  static readonly TOKEN_SPACE_L: number = 16;
  static readonly TOKEN_SPACE_XL: number = 24;
  static readonly TOKEN_SPACE_6: number = 6;
  static readonly TOKEN_SPACE_10: number = 10;
  static readonly TOKEN_SPACE_14: number = 14;
  static readonly TOKEN_SPACE_20: number = 20;
}

// 延时工具：全库唯一实现，供各处「等待固定时长」复用。
export function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout(() => { resolve(); }, ms);
  });
}