import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContext } from './AppContext';
import { Constants } from './Constants';

export class SecureStore {
  private static toU8(s: string): Uint8Array {
    const encoder: util.TextEncoder = new util.TextEncoder();
    return encoder.encodeInto(s);
  }

  private static fromU8(data: Uint8Array): string {
    const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
    return decoder.decodeToString(data);
  }

  static async save(alias: string, secret: string): Promise<void> {
    try {
      const aliasU8: Uint8Array = SecureStore.toU8(alias);
      const rmQuery: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      rmQuery.set(asset.Tag.ALIAS, aliasU8);
      try {
        await asset.remove(rmQuery);
      } catch (e) {}
      const attr: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      attr.set(asset.Tag.ALIAS, aliasU8);
      attr.set(asset.Tag.SECRET, SecureStore.toU8(secret));
      attr.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_POWERED_ON);
      await asset.add(attr);
      return;
    } catch (e) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'asset save failed, fallback to preferences');
    }
    await SecureStore.savePref(alias, secret);
  }

  static async load(alias: string): Promise<string> {
    try {
      const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      query.set(asset.Tag.ALIAS, SecureStore.toU8(alias));
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      const res: asset.AssetMap[] = await asset.query(query);
      if (res.length > 0) {
        const secret: asset.Value | undefined = res[0].get(asset.Tag.SECRET);
        if (secret !== undefined && secret instanceof Uint8Array) {
          return SecureStore.fromU8(secret);
        }
      }
      // asset 查询成功但无记录时同样落到 prefs 兜底——
      // 保存时 asset.add 失败走 prefs 的 cookie，否则冷启动永远读不回（假未登录）
      return SecureStore.loadPref(alias);
    } catch (e) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'asset load failed, fallback to preferences');
    }
    return SecureStore.loadPref(alias);
  }

  static async remove(alias: string): Promise<void> {
    try {
      const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      query.set(asset.Tag.ALIAS, SecureStore.toU8(alias));
      await asset.remove(query);
    } catch (e) {}
    await SecureStore.removePref(alias);
  }

  private static async getPrefs(): Promise<preferences.Preferences> {
    const context = AppContext.require().getApplicationContext();
    return preferences.getPreferences(context, Constants.SECURE_STORE_NAME);
  }

  private static async savePref(alias: string, secret: string): Promise<void> {
    try {
      const prefs: preferences.Preferences = await SecureStore.getPrefs();
      prefs.putSync(Constants.SECURE_PREFIX + alias, secret);
      await prefs.flush();
    } catch (e) {}
  }

  private static async loadPref(alias: string): Promise<string> {
    try {
      const prefs: preferences.Preferences = await SecureStore.getPrefs();
      const value: preferences.ValueType = prefs.getSync(Constants.SECURE_PREFIX + alias, '');
      return value as string;
    } catch (e) {
      return '';
    }
  }

  private static async removePref(alias: string): Promise<void> {
    try {
      const prefs: preferences.Preferences = await SecureStore.getPrefs();
      prefs.deleteSync(Constants.SECURE_PREFIX + alias);
      await prefs.flush();
    } catch (e) {}
  }
}
