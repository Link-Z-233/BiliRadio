import { preferences } from '@kit.ArkData';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BiliVideo } from '../model/BiliVideo';
import { UnfavoriteRecord } from '../model/UnfavoriteRecord';
import { PlayHistoryItem } from '../model/PlayHistoryItem';
import { Constants } from './Constants';
import { FileUtil } from './FileUtil';

export class PlaylistSnapshot {
  items: BiliVideo[] = [];
  lastIndex: number = -1;
  lastPosMs: number = 0;
}

export class AppStore {
  private static prefs: preferences.Preferences | undefined = undefined;

  static async init(): Promise<void> {
    try {
      const context = getContext().getApplicationContext();
      AppStore.prefs = await preferences.getPreferences(context, Constants.STORE_NAME);
    } catch (e) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'AppStore init failed');
    }
  }

  static getNumber(key: string, def: number): number {
    if (AppStore.prefs === undefined) {
      return def;
    }
    const value: preferences.ValueType = AppStore.prefs.getSync(key, def);
    return value as number;
  }

  static getString(key: string, def: string): string {
    if (AppStore.prefs === undefined) {
      return def;
    }
    const value: preferences.ValueType = AppStore.prefs.getSync(key, def);
    return value as string;
  }

  static putNumber(key: string, value: number): void {
    if (AppStore.prefs === undefined) {
      return;
    }
    AppStore.prefs.putSync(key, value);
    AppStore.prefs.flush().catch((): void => {});
  }

  static putString(key: string, value: string): void {
    if (AppStore.prefs === undefined) {
      return;
    }
    AppStore.prefs.putSync(key, value);
    AppStore.prefs.flush().catch((): void => {});
  }

  static savePlaylistFile(items: BiliVideo[], lastIndex: number, lastPosMs: number): void {
    AppStore.putNumber(Constants.KEY_LAST_INDEX, lastIndex);
    AppStore.putNumber(Constants.KEY_LAST_POS_MS, lastPosMs);
    try {
      const context = getContext() as common.UIAbilityContext;
      const path: string = `${context.filesDir}/playlist.json`;
      const itemRecords: Array<Record<string, Object>> = [];
      for (let i = 0; i < items.length; i++) {
        itemRecords.push(items[i].toRecord());
      }
      const rec: Record<string, Object> = {
        'lastIndex': lastIndex,
        'lastPosMs': lastPosMs,
        'items': itemRecords,
      };
      FileUtil.writeTextFile(path, JSON.stringify(rec));
    } catch (e) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'savePlaylistFile failed');
    }
  }

  static loadPlaylistFile(): PlaylistSnapshot {
    const snapshot: PlaylistSnapshot = new PlaylistSnapshot();
    try {
      const context = getContext() as common.UIAbilityContext;
      const path: string = `${context.filesDir}/playlist.json`;
      if (!fs.accessSync(path)) {
        return snapshot;
      }
      const content: string = FileUtil.readTextFile(path);
      if (content === '') {
        return snapshot;
      }
      const root: Record<string, Object> = JSON.parse(content) as Record<string, Object>;
      if (root['items'] !== undefined) {
        const itemRecords: Object[] = root['items'] as Object[];
        for (let i = 0; i < itemRecords.length; i++) {
          const rec: Record<string, Object> = itemRecords[i] as Record<string, Object>;
          snapshot.items.push(BiliVideo.fromRecord(rec));
        }
      }
      if (root['lastIndex'] !== undefined) {
        snapshot.lastIndex = root['lastIndex'] as number;
      }
      if (root['lastPosMs'] !== undefined) {
        snapshot.lastPosMs = root['lastPosMs'] as number;
      }
    } catch (e) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'loadPlaylistFile failed');
    }
    return snapshot;
  }

  static loadUnfavoriteHistory(): UnfavoriteRecord[] {
    const records: UnfavoriteRecord[] = [];
    try {
      const context = getContext() as common.UIAbilityContext;
      const path: string = `${context.filesDir}/unfavorite_history.json`;
      if (!fs.accessSync(path)) {
        return records;
      }
      const content: string = FileUtil.readTextFile(path);
      if (content === '') {
        return records;
      }
      const root: Record<string, Object> = JSON.parse(content) as Record<string, Object>;
      if (root['items'] !== undefined) {
        const itemRecords: Object[] = root['items'] as Object[];
        for (let i = 0; i < itemRecords.length; i++) {
          const rec: Record<string, Object> = itemRecords[i] as Record<string, Object>;
          records.push(UnfavoriteRecord.fromRecord(rec));
        }
      }
    } catch (e) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'loadUnfavoriteHistory failed');
    }
    return records;
  }

  static saveUnfavoriteHistory(items: UnfavoriteRecord[]): void {
    try {
      const context = getContext() as common.UIAbilityContext;
      const path: string = `${context.filesDir}/unfavorite_history.json`;
      const itemRecords: Array<Record<string, Object>> = [];
      for (let i = 0; i < items.length; i++) {
        itemRecords.push(items[i].toRecord());
      }
      const rec: Record<string, Object> = {
        'items': itemRecords,
      };
      FileUtil.writeTextFile(path, JSON.stringify(rec));
    } catch (e) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'saveUnfavoriteHistory failed');
    }
  }

  static loadPlayHistoryFile(): PlayHistoryItem[] {
    const records: PlayHistoryItem[] = [];
    try {
      const context = getContext() as common.UIAbilityContext;
      const path: string = `${context.filesDir}/${Constants.PLAY_HISTORY_FILE}`;
      if (!fs.accessSync(path)) {
        return records;
      }
      const content: string = FileUtil.readTextFile(path);
      if (content === '') {
        return records;
      }
      const root: Record<string, Object> = JSON.parse(content) as Record<string, Object>;
      if (root['items'] !== undefined) {
        const itemRecords: Object[] = root['items'] as Object[];
        for (let i = 0; i < itemRecords.length; i++) {
          const rec: Record<string, Object> = itemRecords[i] as Record<string, Object>;
          const item: PlayHistoryItem = PlayHistoryItem.fromRecord(rec);
          if (item.bvid === '') {
            continue;
          }
          records.push(item);
        }
      }
    } catch (e) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'loadPlayHistoryFile failed');
    }
    return records;
  }

  static savePlayHistoryFile(items: PlayHistoryItem[]): void {
    try {
      const context = getContext() as common.UIAbilityContext;
      const path: string = `${context.filesDir}/${Constants.PLAY_HISTORY_FILE}`;
      const itemRecords: Array<Record<string, Object>> = [];
      for (let i = 0; i < items.length; i++) {
        itemRecords.push(items[i].toRecord());
      }
      const rec: Record<string, Object> = {
        'items': itemRecords,
      };
      FileUtil.writeTextFile(path, JSON.stringify(rec));
    } catch (e) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'savePlayHistoryFile failed');
    }
  }

}
