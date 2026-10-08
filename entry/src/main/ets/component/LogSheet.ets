import { Logger, LogEntry } from '../service/Logger';
import { Constants } from '../service/Constants';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { promptAction } from '@kit.ArkUI';

// 日志懒加载数据源：LazyForEach 只构建可视区域内的条目（缓冲上限 500 条，见 Constants.LOG_BUFFER_MAX）
class LogDataSource implements IDataSource {
  private items: LogEntry[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): LogEntry {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos: number = this.listeners.indexOf(listener);
    if (pos >= 0) {
      this.listeners.splice(pos, 1);
    }
  }

  setItems(next: LogEntry[]): void {
    // 入参可能是 @State 数组的代理对象（重新赋值后代理会更换），拷贝成普通数组避免渲染源失联
    this.items = next.slice(0);
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }
}

// 应用内日志面板（US9）：设置页 bindSheet 承载，只读展示内存环形日志（最新在前）。
// 纯文本条目：时间 / 类别标签（网络/错误）/ 摘要（host+path 或事件名）/ 结果码或错误摘要；
// 面板内清空仅清内存缓冲，不影响任何业务数据。
@Component
export struct LogSheet {
  @State entries: LogEntry[] = [];
  private source: LogDataSource = new LogDataSource();

  aboutToAppear(): void {
    this.reload();
  }

  private reload(): void {
    this.entries = Logger.snapshot();
    this.source.setItems(this.entries);
  }

  private clearLogs(): void {
    Logger.clear();
    this.reload();
  }

  private exportLogs(): void {
    const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(getContext(this));
    const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
    options.newFileNames = [Constants.LOG_FILE_NAME];
    docPicker.save(options).then((uris: Array<string>): void => {
      if (uris.length === 0) {
        return;
      }
      let text: string = '';
      let fromFile: boolean = true;
      try {
        text = Logger.fileText();
      } catch (e) {
        fromFile = false;
        text = Logger.memoryText();
      }
      try {
        const file: fs.File = fs.openSync(uris[0], fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
        try {
          fs.writeSync(file.fd, text);
        } finally {
          fs.closeSync(file);
        }
        promptAction.showToast({
          message: fromFile ? `已导出日志文件 ${text.length} 字符` : '日志文件读取失败，已导出内存缓冲'
        });
      } catch (e) {
        promptAction.showToast({ message: '导出失败' });
      }
    }).catch((): void => {
    });
  }

  private formatTime(time: number): string {
    const d: Date = new Date(time);
    const h: number = d.getHours();
    const m: number = d.getMinutes();
    const s: number = d.getSeconds();
    const hh: string = h < 10 ? `0${h}` : `${h}`;
    const mm: string = m < 10 ? `0${m}` : `${m}`;
    const ss: string = s < 10 ? `0${s}` : `${s}`;
    return `${hh}:${mm}:${ss}`;
  }

  // 'error' → 错误，其余（'net'）→ 网络
  private categoryLabel(category: string): string {
    if (category === 'error') {
      return '错误';
    }
    return '网络';
  }

  build() {
    Column() {
      Row() {
        Text(`日志 (${this.entries.length})`)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Button('导出')
          .height(32)
          .padding({ left: 12, right: 12 })
          .backgroundColor($r('app.color.btn_glass'))
          .backdropBlur(20)
          .border({ width: 1, color: $r('app.color.btn_border') })
          .fontColor($r('app.color.text_primary'))
          .borderRadius(16)
          .fontSize(12)
          .onClick(() => {
            this.exportLogs();
          })
          .margin({ left: 8 })

        if (this.entries.length > 0) {
          Button('清空')
            .height(32)
            .padding({ left: 12, right: 12 })
            .backgroundColor($r('app.color.btn_glass'))
            .backdropBlur(20)
            .border({ width: 1, color: $r('app.color.btn_border') })
            .fontColor($r('app.color.danger_red'))
            .borderRadius(16)
            .fontSize(12)
            .margin({ left: 8 })
            .onClick(() => {
              this.clearLogs();
            })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })

      if (this.entries.length === 0) {
        Column() {
          Text('暂无日志，播放或刷新订阅后会记录网络请求')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 80 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .layoutWeight(1)
      } else {
        List({ space: 0 }) {
          LazyForEach(this.source, (item: LogEntry) => {
            ListItem() {
              Column() {
                Row() {
                  Text(this.formatTime(item.time))
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                  Text(this.categoryLabel(item.category))
                    .fontSize(10)
                    .fontColor(item.category === 'error'
                      ? $r('app.color.danger_red') : $r('app.color.text_secondary'))
                    .padding({ left: 6, right: 6 })
                    .borderRadius(4)
                    .backgroundColor($r('app.color.btn_glass'))
                    .margin({ left: 8 })
                  Blank()
                }
                .width('100%')

                Text(item.summary)
                  .fontSize(13)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: 3 })

                Text(item.result)
                  .fontSize(11)
                  .fontColor(item.category === 'error'
                    ? $r('app.color.danger_red') : $r('app.color.text_secondary'))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            }
          }, (item: LogEntry) => `${item.time}_${item.summary}`)
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.sheet_background'))
  }
}
