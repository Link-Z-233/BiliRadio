import { Constants } from './Constants';
import { connectBool, BoolState } from './V2State';

// 返回分层关闭序列（v0.3-bugfix-round2 US5）：四个返回处理点（Index/SettingsPage/SourcePage/LogPage）
// 共用「先关队列（多选优先退出）→ 再关浮层」序列；队列滑出句柄模块级注册
// （QueueDrawer 挂载点有 Index 内容层与 PlayerOverlay 层两处，宿主成员无法跨 NavDestination 传递）。

let queueCloseHandle: (() => void) | undefined = undefined;

export function registerQueueClose(handle: (() => void) | undefined): void {
  queueCloseHandle = handle;
}

// true=已消化一次返回；false=无浮层可关，调用方走自身后续处理或默认 pop
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
  const showPlayerOverlay: BoolState = connectBool(Constants.AS_SHOW_PLAYER_OVERLAY, false);
  if (showPlayerOverlay.value) {
    const playHistory: BoolState = connectBool(Constants.AS_SHOW_PLAY_HISTORY, false);
    if (playHistory.value) {
      playHistory.value = false;
      return true;
    }
    showPlayerOverlay.value = false;
    return true;
  }
  return false;
}

// 清空队列专用两层同收（R3 US4）：队列经注册句柄滑出（无句柄回退置 flag），
// 播放浮层无条件立即收起，两层同帧无错峰
export function closeBothLayersNow(): void {
  const showQueueSheet: BoolState = connectBool(Constants.AS_SHOW_QUEUE_SHEET, false);
  if (showQueueSheet.value) {
    if (queueCloseHandle !== undefined) {
      queueCloseHandle();
    } else {
      showQueueSheet.value = false;
    }
  }
  connectBool(Constants.AS_SHOW_PLAYER_OVERLAY, false).value = false;
}
