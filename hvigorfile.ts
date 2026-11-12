// @ts-nocheck – Template file, only used when copied into a project directory
import { appTasks, OhosAppContext, OhosPluginId } from '@ohos/hvigor-ohos-plugin';
import { getNode, FileUtil, Json5Reader } from '@ohos/hvigor';

/*
 * 外置签名配置动态加载（官方推荐 hook + 插件上下文方式）：
 *
 * 构建时按以下优先级解析签名配置，经 afterNodeEvaluate hook 注入构建（产物为已签名包）：
 * 1. 优先：工程根目录的 signing.local.json5（被 .gitignore 的 *.local.json5 规则忽略，不入库）；
 * 2. 保底：根 build-profile.json5 中 DevEco 自动签名写入的内联 signingConfigs——仅补 products
 *    的 signingConfig 引用（材料本身不动），材料提交前须手动移出（docs/SECURITY.md）；
 * 3. 两者皆无：不注入任何签名配置，构建照常成功（产物为未签名包）。
 *
 * signing.local.json5 文件格式示例：
 * {
 *   "app": {
 *     "signingConfigs": [
 *       { "name": "default", "type": "HarmonyOS", "material": { ... } }
 *     ]
 *   }
 * }
 */
const SIGNING_LOCAL_FILE = __dirname + '/signing.local.json5';

function bindProductsSigningConfig(appOpt, configName): void {
  const products = appOpt ? appOpt['products'] : undefined;
  if (Array.isArray(products)) {
    for (const product of products) {
      if (!product['signingConfig']) {
        product['signingConfig'] = configName;
      }
    }
  }
}

const rootNode = getNode(__filename);
rootNode.afterNodeEvaluate(node => {
  const appContext = node.getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext;
  const buildProfileOpt = appContext.getBuildProfileOpt();

  // 优先级 1：外置 signing.local.json5
  if (FileUtil.exist(SIGNING_LOCAL_FILE)) {
    const parsed = Json5Reader.getJson5Obj(SIGNING_LOCAL_FILE);
    const appOpt = parsed ? parsed['app'] : undefined;
    const configs =
      (appOpt ? appOpt['signingConfigs'] : undefined) ?? (parsed ? parsed['signingConfigs'] : undefined);
    if (Array.isArray(configs) && configs.length > 0) {
      buildProfileOpt['app']['signingConfigs'] = configs;
      bindProductsSigningConfig(buildProfileOpt['app'], configs[0]['name']);
      appContext.setBuildProfileOpt(buildProfileOpt);
      console.info('[BiliRadio] signing.local.json5 detected: injecting signing config via hvigor hook.');
      return;
    }
    if (parsed && parsed['material']) {
      buildProfileOpt['app']['signingConfigs'] = [
        { name: 'default', type: parsed['type'] || 'HarmonyOS', material: parsed['material'] }
      ];
      bindProductsSigningConfig(buildProfileOpt['app'], 'default');
      appContext.setBuildProfileOpt(buildProfileOpt);
      console.info('[BiliRadio] signing.local.json5 detected: injecting signing config via hvigor hook (direct material format).');
      return;
    }
    console.warn('[BiliRadio] signing.local.json5 exists but contains no signingConfigs; ' +
      'expected shape: { "app": { "signingConfigs": [ { "name": "default", "type": "HarmonyOS", "material": { ... } } ] } }');
    // 文件存在但无有效内容：继续走保底分支
  }

  // 优先级 2（保底）：根文件内联 signingConfigs（DevEco 自动签名写入）
  const inlineConfigs = buildProfileOpt['app']['signingConfigs'];
  if (Array.isArray(inlineConfigs) && inlineConfigs.length > 0) {
    bindProductsSigningConfig(buildProfileOpt['app'], inlineConfigs[0]['name']);
    appContext.setBuildProfileOpt(buildProfileOpt);
    console.info('[BiliRadio] signing.local.json5 absent; using inline signingConfigs from build-profile.json5 ' +
      '(DevEco auto-sign) as fallback.');
    return;
  }

  // 优先级 3：两者皆无，构建未签名包
  console.warn('[BiliRadio] no signing config found (neither signing.local.json5 nor inline signingConfigs in ' +
    'build-profile.json5); building unsigned.');
});

export default {
  system: appTasks /* Built-in plugin of Hvigor. It cannot be modified. */,
  plugins: [] /* Custom plugin to extend the functionality of Hvigor. */,
};
