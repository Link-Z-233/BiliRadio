// @ts-nocheck – Template file, only used when copied into a project directory
import { appTasks } from '@ohos/hvigor-ohos-plugin';
import { FileUtil, Json5Reader } from '@ohos/hvigor';

/*
 * 外置签名配置动态加载（官方签名服务 FAQ faqs-signature-service-19 方式二）：
 *
 * 构建时检测工程根目录的 signing.local.json5（该文件被 .gitignore 的 *.local.json5 规则忽略，不入库）：
 * - 存在：解析其中的 signingConfigs，取首个配置经 hvigor 官方 config.ohos.overrides 机制注入（产物为已签名包）；
 * - 不存在：不注入任何签名配置，构建照常成功（产物为未签名包）。
 *
 * 文件格式与 build-profile.local.json5 一致，示例：
 * {
 *   "app": {
 *     "signingConfigs": [
 *       { "name": "default", "type": "HarmonyOS", "material": { ... } }
 *     ]
 *   }
 * }
 *
 * 根 build-profile.json5 恒保持 signingConfigs: []（空数组基线），签名材料永不写入该文件。
 */
const SIGNING_LOCAL_FILE = __dirname + '/signing.local.json5';

function loadExternalSigningConfig(): Object | undefined {
  if (!FileUtil.exist(SIGNING_LOCAL_FILE)) {
    return undefined; // 外置签名文件不存在：不注入，未签名构建路径（零副作用）
  }
  const parsed: Record<string, Object> = Json5Reader.getJson5Obj(SIGNING_LOCAL_FILE);
  const appOpt: Record<string, Object> | undefined = parsed ? parsed['app'] : undefined;
  const configs: Object[] | undefined =
    (appOpt ? appOpt['signingConfigs'] : undefined) ?? (parsed ? parsed['signingConfigs'] : undefined);
  if (Array.isArray(configs) && configs.length > 0) {
    console.info('[BiliRadio] signing.local.json5 detected: injecting signing config via hvigor overrides.');
    return configs[0];
  }
  if (parsed && parsed['material']) {
    console.info('[BiliRadio] signing.local.json5 detected: injecting signing config via hvigor overrides.');
    return parsed; // 兼容直接书写单个签名配置对象的格式
  }
  console.warn('[BiliRadio] signing.local.json5 exists but contains no signingConfigs; ' +
    'building unsigned. Expected shape: { "app": { "signingConfigs": [ { "name": "default", "type": "HarmonyOS", "material": { ... } } ] } }');
  return undefined;
}

const externalSigningConfig: Object | undefined = loadExternalSigningConfig();

export default {
  system: appTasks /* Built-in plugin of Hvigor. It cannot be modified. */,
  plugins: [] /* Custom plugin to extend the functionality of Hvigor. */,
  // 官方 overrides 通道：存在外置签名配置时注入；不存在时该键为 undefined，构建行为与原模板完全一致
  config: externalSigningConfig
    ? { ohos: { overrides: { signingConfig: externalSigningConfig } } }
    : undefined,
};
