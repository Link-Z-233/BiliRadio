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

// 整行拖选会话（US1 D1 画笔模型）：长按完成时翻转起点行，按翻转后状态锁定画笔方向
// （原未选→加扫、原已选→减扫）；拖动中每次从拖前快照重算选中集——起点至当前行区间按画笔涂刷、
// 区间外恢复快照态（拖回即取消），幂等自纠；位移增量含边缘自动滚动位移（同 SweepSession），
// lastLo/lastHi 缓存已涂区间，区间未变不写回（边缘滚动静止时零渲染压力）；
// 宿主注入行键查询与选中集写回，纯类零装饰器
export class RowDragSession {
  private keyAt: (index: number) => string;
  private writeBack: (selected: Set<string>) => void;
  private startIndex: number = 0;
  private paintAdd: boolean = true;
  private snapshot: Set<string> = new Set<string>();
  private startGlobalY: number = 0;
  private startScrollOffset: number = 0;
  private lastGlobalY: number = 0;
  private lastLo: number = -1;
  private lastHi: number = -1;

  constructor(keyAt: (index: number) => string, writeBack: (selected: Set<string>) => void) {
    this.keyAt = keyAt;
    this.writeBack = writeBack;
  }

  // snapshot 拷贝隔离：后续选中集换引用不影响快照；paintAdd = 起点行翻转后选中与否
  begin(startIndex: number, paintAdd: boolean, snapshot: Set<string>, globalY: number, scrollOffset: number): void {
    this.startIndex = startIndex;
    this.paintAdd = paintAdd;
    this.snapshot = new Set<string>(snapshot);
    this.startGlobalY = globalY;
    this.startScrollOffset = scrollOffset;
    this.lastGlobalY = globalY;
    this.lastLo = -1;
    this.lastHi = -1;
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

  // 快照重算涂刷：脱离区间行恢复拖前状态；行键越界（并发删除/加载）跳过该行不脏写
  applyAt(currentIndex: number): void {
    const lo: number = Math.min(this.startIndex, currentIndex);
    const hi: number = Math.max(this.startIndex, currentIndex);
    if (lo === this.lastLo && hi === this.lastHi) {
      return;
    }
    this.lastLo = lo;
    this.lastHi = hi;
    const next: Set<string> = new Set<string>(this.snapshot);
    for (let i = lo; i <= hi; i++) {
      const key: string = this.keyAt(i);
      if (key === '') {
        continue;
      }
      if (this.paintAdd) {
        next.add(key);
      } else {
        next.delete(key);
      }
    }
    this.writeBack(next);
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
// 每帧滚动后回调场景重算扫选；同方向重复 start 幂等（不重置时钟相位），stop 幂等；
// atEnd 为可选尽头查询（FR-003）：tick 前检查，到顶/到底即停滚清理，缺省不注入时行为不变
export class EdgeAutoScroller {
  private timerId: number = -1;
  private downward: boolean = false;

  start(scroller: Scroller, downward: boolean, onTick: () => void,
    atEnd?: (downward: boolean) => boolean): void {
    if (this.timerId >= 0 && this.downward === downward) {
      return;
    }
    this.stop();
    this.downward = downward;
    this.timerId = setInterval((): void => {
      if (atEnd !== undefined && atEnd(downward)) {
        this.stop();
        return;
      }
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
