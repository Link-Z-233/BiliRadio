import { Constants } from './Constants';

// 应用内日志条目（US9）：仅内存、不落盘。
// time 为毫秒时间戳；category 取 'net'（网络请求）/ 'error'（错误与风控）；
// summary 为事件摘要（网络请求记 host+path，已截掉含 cookie/token 的 query string）；
// result 为结果（'HTTP 200' / 'HTTP 403' / 错误摘要 / '风控页' 等）。
export class LogEntry {
  time: number = 0;
  category: string = 'net';
  summary: string = '';
  result: string = '';
}

// 内存环形日志服务（US9）：全库单点，BiliService 记录网络请求/错误，设置页日志面板（LogSheet）查询。
// 纯内存无 IO；写入全程 try/catch 静默——极端内存压力下日志失败不得影响播放/请求主流程；
// 缓冲超限按 Constants.LOG_BUFFER_MAX 环形淘汰最旧，内存占用有界。
export class Logger {
  private static entries: LogEntry[] = [];

  // 追加一条日志；超限淘汰最旧
  static log(category: string, summary: string, result: string): void {
    try {
      const entry: LogEntry = new LogEntry();
      entry.time = Date.now();
      entry.category = category;
      entry.summary = summary;
      entry.result = result;
      Logger.entries.push(entry);
      if (Logger.entries.length > Constants.LOG_BUFFER_MAX) {
        Logger.entries.splice(0, Logger.entries.length - Constants.LOG_BUFFER_MAX);
      }
    } catch (e) {
      // 静默丢弃：日志写入失败不影响主流程（spec 边界场景）
    }
  }

  // 返回拷贝作为 UI 渲染源：时间倒序（最新在前），不暴露内部数组
  static snapshot(): LogEntry[] {
    try {
      return Logger.entries.slice(0).reverse();
    } catch (e) {
      return [];
    }
  }

  static count(): number {
    return Logger.entries.length;
  }

  static clear(): void {
    Logger.entries = [];
  }
}
