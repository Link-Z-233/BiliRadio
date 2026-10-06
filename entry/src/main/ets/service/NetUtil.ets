import { connection } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from './Constants';

// 网络类型稳定变化防抖窗口（ms）：类型变化后须持续稳定该时长才回调，窗口内回变即取消
const STABLE_NET_DEBOUNCE_MS: number = 3000;

// 网络类型工具：封装 @kit.NetworkKit connection 能力。
// isWifi：判定失败（无网络/权限异常/接口异常）一律按「非 Wi-Fi」保守处理，避免误放行流量敏感操作。
// watchStableNetworkType：默认网络承载类型的稳定变化监听（Wi-Fi/非 Wi-Fi 二值，FR-010 防抖）。
export class NetUtil {
  // —— 稳定网络类型监听（单例注册，进程生命周期内不注销）——
  private static stableWatchRegistered: boolean = false;
  private static stableCallback: ((isWifi: boolean) => void) | undefined = undefined;
  private static stableConn: connection.NetConnection | undefined = undefined;
  // 上次上报的稳定类型基准（注册后异步初始化）；lastSeenWifi 为防抖窗口内观测到的最新类型
  private static hasBaseline: boolean = false;
  private static lastReportedWifi: boolean = false;
  private static lastSeenWifi: boolean = false;
  private static stableDebounceTimerId: number = -1;

  static async isWifi(): Promise<boolean> {
    try {
      const netHandle: connection.NetHandle = await connection.getDefaultNet();
      const capabilities: connection.NetCapabilities = await connection.getNetCapabilities(netHandle);
      const bearers: connection.NetBearType[] = capabilities.bearerTypes;
      for (let i = 0; i < bearers.length; i++) {
        if (bearers[i] === connection.NetBearType.BEARER_WIFI) {
          return true;
        }
      }
      return false;
    } catch (e) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'NetUtil.isWifi check failed');
      return false;
    }
  }

  // 订阅默认网络承载类型的稳定变化：类型相对上次上报值变化后启动防抖定时器，
  // 窗口内回变则取消，到期以最新类型回调一次；注册/事件异常静默 hilog 警告，不影响既有 isWifi
  static watchStableNetworkType(cb: (isWifi: boolean) => void): void {
    NetUtil.stableCallback = cb;
    if (NetUtil.stableWatchRegistered) {
      return;
    }
    try {
      const conn: connection.NetConnection = connection.createNetConnection();
      conn.on('netAvailable', (): void => {
        // 新网络可用后异步重探测默认网络承载类型（netAvailable 不携带能力信息）
        NetUtil.isWifi().then((isWifi: boolean): void => {
          NetUtil.reportStableObservation(isWifi);
        }).catch((): void => {});
      });
      conn.on('netCapabilitiesChange', (info: connection.NetCapabilityInfo): void => {
        const bearers: connection.NetBearType[] = info.netCap.bearerTypes;
        let hasWifi: boolean = false;
        for (let i = 0; i < bearers.length; i++) {
          if (bearers[i] === connection.NetBearType.BEARER_WIFI) {
            hasWifi = true;
            break;
          }
        }
        NetUtil.reportStableObservation(hasWifi);
      });
      conn.on('netUnavailable', (): void => {
        // 网络不可用按非 Wi-Fi 口径观测（与 isWifi 失败保守语义一致）
        NetUtil.reportStableObservation(false);
      });
      conn.register((error: BusinessError) => {
        if (error) {
          hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG,
            'watchStableNetworkType register failed: %{public}s', error.message);
          return;
        }
        // 首次上报基准在注册成功后异步初始化
        NetUtil.isWifi().then((isWifi: boolean): void => {
          NetUtil.reportStableObservation(isWifi);
        }).catch((): void => {});
      });
      NetUtil.stableConn = conn;
      NetUtil.stableWatchRegistered = true;
    } catch (e) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'watchStableNetworkType setup failed');
    }
  }

  // 单次观测合并：观测值==上次上报值→取消挂起定时器（回变）；否则（重新）启动防抖，
  // 到期把最新观测值落为上报基准并回调一次；基准未初始化时仅落基准不回调
  private static reportStableObservation(isWifi: boolean): void {
    if (!NetUtil.hasBaseline) {
      NetUtil.hasBaseline = true;
      NetUtil.lastReportedWifi = isWifi;
      NetUtil.lastSeenWifi = isWifi;
      return;
    }
    if (isWifi === NetUtil.lastReportedWifi) {
      if (NetUtil.stableDebounceTimerId >= 0) {
        clearTimeout(NetUtil.stableDebounceTimerId);
        NetUtil.stableDebounceTimerId = -1;
      }
      return;
    }
    NetUtil.lastSeenWifi = isWifi;
    if (NetUtil.stableDebounceTimerId >= 0) {
      clearTimeout(NetUtil.stableDebounceTimerId);
    }
    NetUtil.stableDebounceTimerId = setTimeout((): void => {
      NetUtil.stableDebounceTimerId = -1;
      NetUtil.lastReportedWifi = NetUtil.lastSeenWifi;
      hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG,
        'stable network type changed: isWifi=%{public}d', NetUtil.lastSeenWifi ? 1 : 0);
      if (NetUtil.stableCallback !== undefined) {
        NetUtil.stableCallback(NetUtil.lastSeenWifi);
      }
    }, STABLE_NET_DEBOUNCE_MS);
  }
}
