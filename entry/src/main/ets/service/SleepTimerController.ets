import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Constants } from './Constants';
import { PlayerController } from './PlayerController';

// 睡眠定时单例：持有倒计时状态、驱动秒级刷新，计时归零时暂停播放并触发提醒回调。
// 倒计时以 Date.now() 墙钟为唯一基准（记录目标时间戳 + 周期刷新），后台/锁屏被节流时切回即可校准，零漂移。
// 状态全部内存态、不持久化，进程重启自然回到默认不开启。
export class SleepTimerController {
  private static instance: SleepTimerController | undefined = undefined;

  static getInstance(): SleepTimerController {
    if (SleepTimerController.instance === undefined) {
      SleepTimerController.instance = new SleepTimerController();
    }
    return SleepTimerController.instance;
  }

  active: boolean = false;
  totalSeconds: number = 0;
  lastSelectedSeconds: number = 0;
  onTimerExpired: (() => void) | undefined = undefined;

  private endTime: number = 0;
  private timerId: number = -1;
  private listeners: Array<() => void> = [];
  // 与 listeners 按下标对应的 owner 标识（KI-5）：支撑同 owner 单槽覆盖
  private listenerOwners: Array<string> = [];
  private lastEmittedSec: number = -1;

  // 订阅 UI 刷新（KI-2）：返回退订句柄，调用方须在 aboutToDisappear 中调用，
  // 避免播放层反复挂载导致监听器累积；owner 为调用方标识，用于生命周期日志追溯。
  // KI-5：非空 owner 采用单槽覆盖——同 owner 重复订阅时先移除旧监听器再压入新的，
  // 防止 API 24 伪 aboutToDisappear 时序下漏退订造成的累积（与 PlayerController.subscribe 同型）。
  subscribe(fn: () => void, owner: string = ''): () => void {
    if (owner !== '') {
      for (let i = this.listeners.length - 1; i >= 0; i--) {
        if (this.listenerOwners[i] === owner) {
          this.listeners.splice(i, 1);
          this.listenerOwners.splice(i, 1);
        }
      }
      this.listeners.push(fn);
      this.listenerOwners.push(owner);
    } else if (this.listeners.indexOf(fn) < 0) {
      this.listeners.push(fn);
      this.listenerOwners.push('');
    }
    hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG,
      'sleep timer subscribe%{public}s listeners=%{public}d',
      owner !== '' ? ` owner=${owner}` : '', this.listeners.length);
    return (): void => {
      const idx: number = this.listeners.indexOf(fn);
      if (idx >= 0) {
        this.listeners.splice(idx, 1);
        this.listenerOwners.splice(idx, 1);
      }
      hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG,
        'sleep timer unsubscribe%{public}s listeners=%{public}d',
        owner !== '' ? ` owner=${owner}` : '', this.listeners.length);
    };
  }

  private emitUi(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      try {
        this.listeners[i]();
      } catch (e) {
        hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'sleep timer emitUi listener error');
      }
    }
  }

  startTimer(seconds: number): void {
    if (seconds <= 0) {
      return;
    }
    this.stopTick();
    this.totalSeconds = seconds;
    this.lastSelectedSeconds = seconds;
    this.endTime = Date.now() + seconds * 1000;
    this.active = true;
    this.lastEmittedSec = -1;
    hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'sleep timer start: %{public}d s', seconds);
    this.startTick();
    this.emitUi();
  }

  cancelTimer(): void {
    this.stopTick();
    this.active = false;
    this.totalSeconds = 0;
    this.endTime = 0;
    this.lastEmittedSec = -1;
    hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'sleep timer cancel');
    this.emitUi();
  }

  restartTimer(): void {
    if (this.lastSelectedSeconds > 0) {
      this.startTimer(this.lastSelectedSeconds);
    }
  }

  getRemainingSeconds(): number {
    if (!this.active) {
      return 0;
    }
    const remain: number = Math.ceil((this.endTime - Date.now()) / 1000);
    return remain < 0 ? 0 : remain;
  }

  private startTick(): void {
    this.timerId = setInterval((): void => {
      this.onTick();
    }, Constants.SLEEP_TIMER_TICK_MS);
  }

  private stopTick(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private onTick(): void {
    const remaining: number = this.getRemainingSeconds();
    if (remaining <= 0) {
      this.stopTick();
      this.active = false;
      this.totalSeconds = 0;
      this.endTime = 0;
      this.lastEmittedSec = -1;
      this.emitUi();
      hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'sleep timer expired');
      PlayerController.getInstance().pauseRequest().catch((err: BusinessError): void => {
        hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'sleep timer pause failed: %{public}s', err.message);
      });
      try {
        if (this.onTimerExpired !== undefined) {
          this.onTimerExpired();
        }
      } catch (e) {
        hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'sleep timer expired callback error');
      }
      return;
    }
    if (remaining !== this.lastEmittedSec) {
      this.lastEmittedSec = remaining;
      this.emitUi();
    }
  }
}