import { Constants } from './Constants';
import { connectBool, BoolState } from './V2State';

// 返回链统一入口（v0.4-Part2 z-layer-refactor）：去路由化后系统返回仅达 Index @Entry，
// dismissOverlaysForBack 按层自上而下逐层关闭（队列→播放层附属面板→播放层→日志层→设置层句柄→设置层），
// 层物理堆叠保证链命中的永远是当前最上层；队列滑出句柄与设置层内部句柄均模块级注册（宿主生命周期上报）。

let queueCloseHandle: (() => void) | undefined = undefined;
let settingsBackHandle: (() => boolean) | undefined = undefined;

export function registerQueueClose(handle: (() => void) | undefined): void {
  queueCloseHandle = handle;
}

export function registerSettingsBack(handle: (() => boolean) | undefined): void {
  settingsBackHandle = handle;
}

// true=已消化一次返回；false=无层可关，调用方走默认行为
export function dismissOverlaysForBack(): boolean {
  const showQueueSheet: BoolState = connectBool(Constants.AS_SHOW_QUEUE_SHEET, false);
  if (showQueueSheet.value) {
    const selectMode: BoolState = connectBool(Constants.AS_PLAYLIST_SELECT_MODE, false);
    if (selectMode.value) {
      selectMode.value = false;
      return true;
    }
    if (queueCloseHandle !== undefined) {
      queueCloseHandle();
    } else {
      showQueueSheet.value = false;
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
