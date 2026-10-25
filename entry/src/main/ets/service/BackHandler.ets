import { Constants } from './Constants';
import { connectBool, BoolState } from './V2State';

// 返回链统一入口（v0.4-Part2 z-layer-refactor）：去路由化后系统返回仅达 Index @Entry，
// dismissOverlaysForBack 按层自上而下逐层关闭（首页编辑模式→队列→历史面板→播放层附属面板→播放层→日志层→设置层句柄→设置层），
// 层物理堆叠保证链命中的永远是当前最上层；各层滑出句柄与设置层内部句柄均模块级注册（宿主生命周期上报）。

let queueCloseHandle: (() => void) | undefined = undefined;
let historyCloseHandle: (() => void) | undefined = undefined;
let settingsBackHandle: (() => boolean) | undefined = undefined;
// 首页订阅排序编辑模式退出句柄（v0.6-part3）：编辑态由首页 @Local 持有（无全局 flag），
// 句柄内自判编辑态——true=处于编辑态并已消化返回，false=非编辑态放行后续层
let homeEditBackHandle: (() => boolean) | undefined = undefined;
// 多选动画退选句柄（FR-008）：队列/历史组件注册组件内动画退出（BackHandler 无 UIContext 不能
// animateTo），未注册回退直翻保证异常时序不崩溃
let queueSelectExitHandle: (() => void) | undefined = undefined;
let historySelectExitHandle: (() => void) | undefined = undefined;

export function registerQueueClose(handle: (() => void) | undefined): void {
  queueCloseHandle = handle;
}

export function registerHistoryClose(handle: (() => void) | undefined): void {
  historyCloseHandle = handle;
}

export function registerSettingsBack(handle: (() => boolean) | undefined): void {
  settingsBackHandle = handle;
}

export function registerHomeEditBack(handle: (() => boolean) | undefined): void {
  homeEditBackHandle = handle;
}

export function registerQueueSelectExit(handle: (() => void) | undefined): void {
  queueSelectExitHandle = handle;
}

export function registerHistorySelectExit(handle: (() => void) | undefined): void {
  historySelectExitHandle = handle;
}

// true=已消化一次返回；false=无层可关，调用方走默认行为
export function dismissOverlaysForBack(): boolean {
  if (homeEditBackHandle !== undefined && homeEditBackHandle()) {
    return true;
  }
  const showQueueSheet: BoolState = connectBool(Constants.AS_SHOW_QUEUE_SHEET, false);
  if (showQueueSheet.value) {
    const selectMode: BoolState = connectBool(Constants.AS_PLAYLIST_SELECT_MODE, false);
    if (selectMode.value) {
      if (queueSelectExitHandle !== undefined) {
        queueSelectExitHandle();
      } else {
        selectMode.value = false;
      }
      return true;
    }
    if (queueCloseHandle !== undefined) {
      queueCloseHandle();
    } else {
      showQueueSheet.value = false;
    }
    return true;
  }
  // 历史面板（L4 独立层）：多选优先退多选，再滑出面板
  const showPlayHistory: BoolState = connectBool(Constants.AS_SHOW_PLAY_HISTORY, false);
  if (showPlayHistory.value) {
    const historySelectMode: BoolState = connectBool(Constants.AS_HISTORY_SELECT_MODE, false);
    if (historySelectMode.value) {
      if (historySelectExitHandle !== undefined) {
        historySelectExitHandle();
      } else {
        historySelectMode.value = false;
      }
      return true;
    }
    if (historyCloseHandle !== undefined) {
      historyCloseHandle();
    } else {
      showPlayHistory.value = false;
    }
    return true;
  }
  const showSpeed: BoolState = connectBool(Constants.AS_SHOW_SPEED, false);
  if (showSpeed.value) {
    showSpeed.value = false;
    return true;
  }
  const showMode: BoolState = connectBool(Constants.AS_SHOW_MODE, false);
  if (showMode.value) {
    showMode.value = false;
    return true;
  }
  const showSleepTimerPicker: BoolState = connectBool(Constants.AS_SHOW_SLEEP_TIMER_PICKER, false);
  if (showSleepTimerPicker.value) {
    showSleepTimerPicker.value = false;
    return true;
  }
  const showSleepTimer: BoolState = connectBool(Constants.AS_SHOW_SLEEP_TIMER, false);
  if (showSleepTimer.value) {
    showSleepTimer.value = false;
    return true;
  }
  const showPlayerOverlay: BoolState = connectBool(Constants.AS_SHOW_PLAYER_OVERLAY, false);
  if (showPlayerOverlay.value) {
    showPlayerOverlay.value = false;
    return true;
  }
  const showLogPage: BoolState = connectBool(Constants.AS_SHOW_LOG_PAGE, false);
  if (showLogPage.value) {
    showLogPage.value = false;
    return true;
  }
  if (settingsBackHandle !== undefined && settingsBackHandle()) {
    return true;
  }
  const showSettingsPage: BoolState = connectBool(Constants.AS_SHOW_SETTINGS_PAGE, false);
  if (showSettingsPage.value) {
    showSettingsPage.value = false;
    return true;
  }
  return false;
}

// 清空队列专用两层同收（R3 US4 / R4 US1）：浮层内实例两标志同帧直复位随浮层一次性退出
// （不调用滑出句柄、不起延时器）；首页层实例保持队列经注册句柄滑出（无句柄回退置 flag），
// 播放浮层无条件立即收起，两层同帧无错峰
export function closeBothLayersNow(): void {
  const showQueueSheet: BoolState = connectBool(Constants.AS_SHOW_QUEUE_SHEET, false);
  const showPlayerOverlay: BoolState = connectBool(Constants.AS_SHOW_PLAYER_OVERLAY, false);
  if (showPlayerOverlay.value) {
    showQueueSheet.value = false;
    showPlayerOverlay.value = false;
    return;
  }
  if (showQueueSheet.value) {
    if (queueCloseHandle !== undefined) {
      queueCloseHandle();
    } else {
      showQueueSheet.value = false;
    }
  }
  showPlayerOverlay.value = false;
}
