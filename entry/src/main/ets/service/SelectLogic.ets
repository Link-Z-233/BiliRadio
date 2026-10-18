// 多选共享逻辑（FR-012）：Set 引用替换勾选切换 + 长按守卫，订阅源/队列/历史三处共用
import { Constants } from './Constants';

export class SelectLogic {
  // 勾选切换（引用替换）：已有则删、无则加，返回新 Set 由调用方整体换引用（V2 赋值观测模式）
  static toggle(selected: Set<string>, key: string): Set<string> {
    const next: Set<string> = new Set<string>(selected);
    if (next.has(key)) {
      next.delete(key);
    } else {
      next.add(key);
    }
    return next;
  }
}

// 长按守卫（FR-009）：长按触发置位，随后 ArkUI 回退派发的 onClick 命中即吞掉并复位，
// 下次按下（TouchType.Down）重置；堵 Sequence 手势组失败后的回退点击取消预选，拖选路径不受影响
export class LongPressGuard {
  private armed: boolean = false;

  arm(): void {
    this.armed = true;
  }

  shouldSuppressClick(): boolean {
    if (this.armed) {
      this.armed = false;
      return true;
    }
    return false;
  }

  reset(): void {
    this.armed = false;
  }
}

// 拖选会话（FR-014，追加2）：按下采样锁定加/减扫模式（起点行未选=加扫、已选=减扫，同次拖动不反转），
// 记录起点行 index/全局 Y/滚动偏移；位移增量 =（globalY−startGlobalY）+（currentOffset−startScrollOffset），
// 覆盖边缘自动滚动带来的内容位移；纯类零装饰器，场景侧持实例、手势回调驱动
export class SweepSession {
  private addMode: boolean = false;
  private startIndex: number = 0;
  private startGlobalY: number = 0;
  private startScrollOffset: number = 0;
  private lastGlobalY: number = 0;

  begin(startRowSelected: boolean, startIndex: number, globalY: number, scrollOffset: number): void {
    this.addMode = !startRowSelected;
    this.startIndex = startIndex;
    this.startGlobalY = globalY;
    this.startScrollOffset = scrollOffset;
    this.lastGlobalY = globalY;
  }

  isAddMode(): boolean {
    return this.addMode;
  }

  getStartIndex(): number {
    return this.startIndex;
  }

  getLastGlobalY(): number {
    return this.lastGlobalY;
  }

  delta(globalY: number, scrollOffset: number): number {
    this.lastGlobalY = globalY;
    return (globalY - this.startGlobalY) + (scrollOffset - this.startScrollOffset);
  }
}

// 边缘自动滚动器（FR-018，追加2）：拖选中手指静止时 Pan 无 update 事件，
// 内部 setInterval 时钟驱动 scroller.scrollBy（走列表既有滚动管线，触底 onReachEnd 语义继承），
// 每帧滚动后回调场景重算扫选；同方向重复 start 幂等（不重置时钟相位），stop 幂等
export class EdgeAutoScroller {
  private timerId: number = -1;
  private downward: boolean = false;

  start(scroller: Scroller, downward: boolean, onTick: () => void): void {
    if (this.timerId >= 0 && this.downward === downward) {
      return;
    }
    this.stop();
    this.downward = downward;
    this.timerId = setInterval((): void => {
      const dy: number = downward ? Constants.SELECT_SWEEP_SPEED : -Constants.SELECT_SWEEP_SPEED;
      scroller.scrollBy(0, dy);
      onTick();
    }, Constants.SELECT_SWEEP_TICK_MS);
  }

  stop(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }
}
