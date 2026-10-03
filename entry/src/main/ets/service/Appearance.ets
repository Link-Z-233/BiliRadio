import { Configuration, ConfigurationConstant, common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Constants } from './Constants';

// 窗口层 API（setWindowBackgroundColor / SystemBarProperties）仅接受字符串色值，
// 无法借 base/dark 资源目录自动匹配，需按当前生效外观手动映射，并在模式变化时重新设置。
// 受限色值已集中到 Constants（WIN_BG_*/BAR_CONTENT_*/PROBE_DARK_RGB），此处不再重复声明。

/**
 * 外观三态（跟随系统/浅色/深色）管理：
 * - 持久化键 colorMode（biliradio_store），0=跟随系统 1=浅色 2=深色，缺省/读取失败回退跟随系统。
 * - 启动阶段（EntryAbility.onCreate）自行 getPreferencesSync 读取，不依赖 PlayerController 里的 AppStore.init 时机。
 * - 应用层通过 getApplicationContext().setColorMode() 生效，base/dark 资源目录自动匹配。
 * - 窗口层（窗口背景、状态栏/导航栏前景）按生效外观手动映射色值。
 * - AppStorage 同步：colorModeSetting（用户选择）、colorModeResolved（生效深浅）、
 *   accentColor（主题色，限预设色板，默认 B 站粉）。
 */
export class Appearance {
  static readonly KEY_COLOR_MODE: string = Constants.KEY_COLOR_MODE;
  static readonly KEY_ACCENT_COLOR: string = Constants.KEY_ACCENT_COLOR;
  static readonly MODE_FOLLOW_SYSTEM: number = 0;
  static readonly MODE_LIGHT: number = 1;
  static readonly MODE_DARK: number = 2;

  private static userMode: number = Appearance.MODE_FOLLOW_SYSTEM;
  private static isDark: boolean = false;
  private static mainWindow: window.Window | undefined = undefined;

  static getUserMode(): number {
    return Appearance.userMode;
  }

  static isDarkNow(): boolean {
    return Appearance.isDark;
  }

  // EntryAbility.onCreate：读取持久化外观并应用应用层颜色模式
  static init(context: common.Context): void {
    Appearance.userMode = Appearance.readUserMode(context);
    Appearance.applyAppColorMode(context);
    if (Appearance.userMode === Appearance.MODE_LIGHT) {
      Appearance.isDark = false;
    } else if (Appearance.userMode === Appearance.MODE_DARK) {
      Appearance.isDark = true;
    } else {
      // 跟随系统：NOT_SET 下资源按系统当前模式解析，探测准确
      Appearance.refreshResolved(context, true);
    }
    AppStorage.setOrCreate<string>(Constants.AS_ACCENT_COLOR, Appearance.readAccentColor(context));
    Appearance.syncAppStorage();
  }

  // 设置页选择外观：持久化 + 应用层模式 + 窗口层颜色即时生效（无需重启）
  static setUserMode(mode: number, context: common.Context): void {
    if (mode !== Appearance.MODE_FOLLOW_SYSTEM && mode !== Appearance.MODE_LIGHT &&
      mode !== Appearance.MODE_DARK) {
      return;
    }
    Appearance.userMode = mode;
    try {
      const options: preferences.Options = { name: Constants.STORE_NAME };
      const prefs: preferences.Preferences = preferences.getPreferencesSync(context, options);
      prefs.putSync(Appearance.KEY_COLOR_MODE, mode);
      prefs.flushSync();
    } catch (err) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'persist colorMode failed');
    }
    Appearance.applyAppColorMode(context);
    if (mode === Appearance.MODE_LIGHT) {
      Appearance.isDark = false;
    } else if (mode === Appearance.MODE_DARK) {
      Appearance.isDark = true;
    } else {
      // 切回跟随系统：按系统当前模式重新确定生效深浅
      Appearance.refreshResolved(context, false);
    }
    Appearance.syncAppStorage();
    Appearance.applyWindowColors();
  }

  // UIAbility.onConfigurationUpdate：仅「跟随系统」时联动窗口层与状态；
  // 强制浅/深时系统配置变化不改变用户选择（保持所选外观）。
  static handleConfiguration(config: Configuration, context: common.Context): void {
    if (Appearance.userMode !== Appearance.MODE_FOLLOW_SYSTEM) {
      return;
    }
    if (config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK) {
      Appearance.isDark = true;
    } else if (config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT) {
      Appearance.isDark = false;
    } else {
      Appearance.refreshResolved(context, false);
    }
    Appearance.syncAppStorage();
    Appearance.applyWindowColors();
  }

  // EntryAbility.onWindowStageCreate：接管窗口引用后立即按生效外观设置窗口层颜色
  static attachWindow(mainWindow: window.Window): void {
    Appearance.mainWindow = mainWindow;
    Appearance.applyWindowColors();
  }

  // 按当前生效外观重设窗口背景与状态栏/导航栏前景图标颜色
  static applyWindowColors(): void {
    const win: window.Window | undefined = Appearance.mainWindow;
    if (win === undefined) {
      return;
    }
    const bg: string = Appearance.isDark ? Constants.WIN_BG_DARK : Constants.WIN_BG_LIGHT;
    const fg: string = Appearance.isDark ? Constants.BAR_CONTENT_DARK : Constants.BAR_CONTENT_LIGHT;
    try {
      // 全屏布局生效后才可设置（过早调用会报 1300002），由 attachWindow 时序保证；
      // setWindowBackgroundColor 为同步接口（返回 void，无 Promise），异常由外层 try-catch 兜底
      win.setWindowBackgroundColor(bg);
      const props: window.SystemBarProperties = {
        statusBarColor: 'rgba(0, 0, 0, 0)',
        statusBarContentColor: fg,
        navigationBarColor: 'rgba(0, 0, 0, 0)',
        navigationBarContentColor: fg
      };
      win.setWindowSystemBarProperties(props)
        .catch((err: BusinessError): void => {
          hilog.error(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'setWindowSystemBarProperties failed');
        });
    } catch (err) {
      hilog.error(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'applyWindowColors failed');
    }
  }

  // 设置页选择主题色：持久化 + AppStorage 即时生效（仅接受预设色板内取值）
  static setAccentColor(color: string, context: common.Context): void {
    if (!Appearance.isValidAccent(color)) {
      return;
    }
    try {
      const options: preferences.Options = { name: Constants.STORE_NAME };
      const prefs: preferences.Preferences = preferences.getPreferencesSync(context, options);
      prefs.putSync(Appearance.KEY_ACCENT_COLOR, color);
      prefs.flushSync();
    } catch (err) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'persist accentColor failed');
    }
    AppStorage.setOrCreate<string>(Constants.AS_ACCENT_COLOR, color);
  }

  private static readAccentColor(context: common.Context): string {
    try {
      const options: preferences.Options = { name: Constants.STORE_NAME };
      const prefs: preferences.Preferences = preferences.getPreferencesSync(context, options);
      const value: preferences.ValueType =
        prefs.getSync(Appearance.KEY_ACCENT_COLOR, Constants.ACCENT_DEFAULT);
      const color: string = value as string;
      if (Appearance.isValidAccent(color)) {
        return color;
      }
      return Constants.ACCENT_DEFAULT;
    } catch (err) {
      // 首次安装（无值）或存储不可用：回退默认 B 站粉
      return Constants.ACCENT_DEFAULT;
    }
  }

  private static isValidAccent(color: string): boolean {
    return typeof color === 'string' && Constants.ACCENT_PRESETS.indexOf(color) >= 0;
  }

  private static readUserMode(context: common.Context): number {
    try {
      const options: preferences.Options = { name: Constants.STORE_NAME };
      const prefs: preferences.Preferences = preferences.getPreferencesSync(context, options);
      const value: preferences.ValueType =
        prefs.getSync(Appearance.KEY_COLOR_MODE, Appearance.MODE_FOLLOW_SYSTEM);
      const mode: number = value as number;
      if (mode === Appearance.MODE_LIGHT || mode === Appearance.MODE_DARK ||
        mode === Appearance.MODE_FOLLOW_SYSTEM) {
        return mode;
      }
      return Appearance.MODE_FOLLOW_SYSTEM;
    } catch (err) {
      // 首次安装（无值）或存储不可用：回退为跟随系统
      return Appearance.MODE_FOLLOW_SYSTEM;
    }
  }

  private static applyAppColorMode(context: common.Context): void {
    try {
      const appContext = context.getApplicationContext();
      if (Appearance.userMode === Appearance.MODE_LIGHT) {
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      } else if (Appearance.userMode === Appearance.MODE_DARK) {
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      } else {
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      }
    } catch (err) {
      hilog.error(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'setColorMode failed');
    }
  }

  // 跟随系统时按资源实际解析结果判定当前深浅（NOT_SET 下资源按系统模式匹配）
  private static refreshResolved(context: common.Context, initial: boolean): void {
    try {
      const rm = context.resourceManager;
      const color: number = rm.getColorByNameSync('app.color.page_background');
      Appearance.isDark = (color & 0xFFFFFF) === Constants.PROBE_DARK_RGB;
    } catch (err) {
      if (initial) {
        Appearance.isDark = false;
      }
    }
  }

  // 同步到 AppStorage：设置页选中态、底栏联动等 UI 由此驱动
  private static syncAppStorage(): void {
    AppStorage.setOrCreate<number>(Constants.AS_COLOR_MODE_SETTING, Appearance.userMode);
    AppStorage.setOrCreate<number>(Constants.AS_COLOR_MODE_RESOLVED,
      Appearance.isDark ? Appearance.MODE_DARK : Appearance.MODE_LIGHT);
  }
}