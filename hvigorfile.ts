// @ts-nocheck – Template file, only used when copied into a project directory
import { appTasks, OhosAppContext, OhosPluginId } from '@ohos/hvigor-ohos-plugin';
import { getNode, FileUtil, Json5Reader } from '@ohos/hvigor';

/*
 * 外置签名配置动态加载（官方推荐 hook + 插件上下文方式）：
 *
 * 构建时检测工程根目录的 signing.local.json5（该文件被 .gitignore 的 *.local.json5 规则忽略，不入库）：
 * - 存在：解析其中的 signingConfigs，经 hvigor afterNodeEvaluate hook 注入到构建配置（产物为已签名包）；
 * - 不存在：不注入任何签名配置，构建照常成功（产物为未签名包）。
 *
 * 文件格式示例：
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

const rootNode = getNode(__filename);
rootNode.afterNodeEvaluate(node => {
  if (!FileUtil.exist(SIGNING_LOCAL_FILE)) {
    return;
  }
  const parsed = Json5Reader.getJson5Obj(SIGNING_LOCAL_FILE);
  const appOpt = parsed ? parsed['app'] : undefined;
  const configs =
    (appOpt ? appOpt['signingConfigs'] : undefined) ?? (parsed ? parsed['signingConfigs'] : undefined);
  if (Array.isArray(configs) && configs.length > 0) {
    const appContext = node.getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext;
    const buildProfileOpt = appContext.getBuildProfileOpt();
    buildProfileOpt['app']['signingConfigs'] = configs;
    const products = buildProfileOpt['app']['products'];
    if (Array.isArray(products)) {
      for (const product of products) {
        if (!product['signingConfig']) {
          product['signingConfig'] = configs[0]['name'];
        }
      }
    }
    appContext.setBuildProfileOpt(buildProfileOpt);
    console.info('[BiliRadio] signing.local.json5 detected: injecting signing config via hvigor hook.');
  } else if (parsed && parsed['material']) {
    const appContext = node.getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext;
    const buildProfileOpt = appContext.getBuildProfileOpt();
    buildProfileOpt['app']['signingConfigs'] = [
      { name: 'default', type: parsed['type'] || 'HarmonyOS', material: parsed['material'] }
    ];
    const products = buildProfileOpt['app']['products'];
    if (Array.isArray(products)) {
      for (const product of products) {
        if (!product['signingConfig']) {
          product['signingConfig'] = 'default';
        }
      }
    }
    appContext.setBuildProfileOpt(buildProfileOpt);
    console.info('[BiliRadio] signing.local.json5 detected: injecting signing config via hvigor hook (direct material format).');
  } else {
    console.warn('[BiliRadio] signing.local.json5 exists but contains no signingConfigs; ' +
      'building unsigned. Expected shape: { "app": { "signingConfigs": [ { "name": "default", "type": "HarmonyOS", "material": { ... } } ] } }');
  }
});

export default {
  system: appTasks /* Built-in plugin of Hvigor. It cannot be modified. */,
  plugins: [] /* Custom plugin to extend the functionality of Hvigor. */,
};
