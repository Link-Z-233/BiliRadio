import { connection } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from './Constants';

// 网络类型工具：封装 @kit.NetworkKit connection 能力，对外仅暴露 isWifi 判定。
// 判定失败（无网络/权限异常/接口异常）一律按「非 Wi-Fi」保守处理，避免误放行流量敏感操作。
export class NetUtil {
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
}