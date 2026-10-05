import { Constants } from './Constants';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';

// 应用内日志条目（US9）：内存环形缓冲 + 异步落盘。
// time 为毫秒时间戳；category 取 'net'（网络请求）/ 'error'（错误与风控）/ 'player'（播放链路诊断）；
// summary 为事件摘要（网络请求记 host+path，已截掉含 cookie/token 的 query string）；
// result 为结果（'HTTP 200' / 'HTTP 403' / 错误摘要 / '风控页' 等）。
export class LogEntry {
  time: number = 0;
  category: string = 'net';
  summary: string = '';
  result: string = '';
}

// 日志服务（US9）：全库单点，BiliService 记录网络请求/错误，PlayerController 记录播放链路诊断，
// 设置页日志面板（LogSheet）查询内存缓冲。
// 内存侧：环形缓冲超限按 Constants.LOG_BUFFER_MAX 淘汰最旧，占用有界；
// 落盘侧（US9 新增）：每条日志以单行可读格式异步追加写入沙箱 filesDir 下日志文件，
// fire-and-forget 不阻塞主流程，写入全程 try/catch 静默——极端 IO 压力下落盘失败不得影响播放/请求主流程；
// 每次（批量）写入前检查文件大小，超 Constants.LOG_FILE_MAX_BYTES 保留最新一半重写（滚动淘汰，字节级有界）；
// 启动不回读（内存缓冲与文件相互独立）；clear() 仅清内存，不删文件。
export class Logger {
  private static entries: LogEntry[] = [];
  // US9：落盘写链——串行化追加，避免并发写交错；链上失败静默后继续接后续写入
  private static fileWriteChain: Promise<void> = Promise.resolve();
  // 沙箱日志文件路径缓存（ getContext 首次成功后固定）
  private static filePathCache: string = '';

  // 追加一条日志；内存超限淘汰最旧；同时 fire-and-forget 落盘
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
      Logger.appendFile(Logger.buildFileLine(category, summary, result));
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

  // —— 以下为 US9 落盘实现（全部静默失败） ——

  // 沙箱日志文件路径：filesDir/biliradio_log.txt，首次取到后缓存
  private static logFilePath(): string {
    if (Logger.filePathCache !== '') {
      return Logger.filePathCache;
    }
    try {
      const context = getContext() as common.UIAbilityContext;
      Logger.filePathCache = `${context.filesDir}/${Constants.LOG_FILE_NAME}`;
    } catch (e) {
      Logger.filePathCache = '';
    }
    return Logger.filePathCache;
  }

  // 单行可读格式：`yyyy-MM-dd HH:mm:ss.SS [category] summary | result`；
  // 内部换行归一为空格，保证一行一条日志
  private static buildFileLine(category: string, summary: string, result: string): string {
    const flatten = (s: string): string => s.split('\n').join(' ').split('\r').join(' ');
    const d: Date = new Date(Date.now());
    const pad = (v: number): string => v < 10 ? `0${v}` : `${v}`;
    const time: string = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ` +
      `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}.` +
      `${pad(Math.floor(d.getMilliseconds() / 10))}`;
    return `${time} [${flatten(category)}] ${flatten(summary)} | ${flatten(result)}\n`;
  }

  // 追加写入写链：串行执行，失败静默不断链
  private static appendFile(line: string): void {
    Logger.fileWriteChain = Logger.fileWriteChain.then((): Promise<void> => {
      return Logger.writeLine(line);
    }).catch((): void => {
      // 静默：单条落盘失败不影响后续写入
    });
  }

  // 写入单行：写前检查硬上限，超限先滚动淘汰（保留最新一半）再追加
  private static async writeLine(line: string): Promise<void> {
    const path: string = Logger.logFilePath();
    if (path === '') {
      return;
    }
    try {
      let rotated: boolean = false;
      try {
        const stat: fs.Stat = fs.statSync(path);
        // 字符数近似字节上限（UTF-8 多字节字符会低估，硬上限由滚动机制兜底收敛）
        if (stat.size + line.length > Constants.LOG_FILE_MAX_BYTES) {
          await Logger.rotateFile(path, stat.size);
          rotated = true;
        }
      } catch (e) {
        // 文件不存在（首次写入）或 stat 失败：直接走追加建文件
      }
      const file: fs.File = fs.openSync(path, fs.OpenMode.APPEND | fs.OpenMode.CREATE);
      try {
        fs.writeSync(file.fd, line);
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      // 落盘失败静默：不影响主流程（spec 边界场景）
    }
  }

  // 滚动淘汰：保留文件后一半字节，并对齐到首个完整行边界（0x0A），经 .tmp 重写原文件；
  // 纯字节搬运不做文本解码，避免多字节字符截断问题
  private static async rotateFile(path: string, size: number): Promise<void> {
    if (size <= 0) {
      return;
    }
    const file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const start: number = Math.floor(size / 2);
      const bufLen: number = size - start;
      const buf: ArrayBuffer = new ArrayBuffer(bufLen);
      fs.readSync(file.fd, buf, { offset: start, length: bufLen });
      const bytes: Uint8Array = new Uint8Array(buf);
      let cut: number = 0;
      while (cut < bytes.length && bytes[cut] !== 0x0A) {
        cut++;
      }
      if (cut < bytes.length) {
        cut++; // 从 \n 之后的完整行起保留
      } else {
        cut = 0; // 后半段无完整行（极端情况）：原样保留，待下次写入再滚动
      }
      const keepLen: number = bufLen - cut;
      if (keepLen <= 0) {
        return;
      }
      const keep: ArrayBuffer = buf.slice(cut, bufLen);
      const tmpPath: string = `${path}.tmp`;
      const tmp: fs.File =
        fs.openSync(tmpPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(tmp.fd, keep);
      } finally {
        fs.closeSync(tmp);
      }
      fs.renameSync(tmpPath, path);
    } catch (e) {
      // 滚动失败静默：文件暂超上限，下次写入会重试滚动
    } finally {
      fs.closeSync(file);
    }
  }
}
