import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_fund/core/config.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  test('Selective Export and Import JSON test', () async {
    final appConfig = AppConfig();
    final tempDir = Directory.systemTemp.createTempSync();
    appConfig.customConfigPath = '${tempDir.path}/my_funds_test.json';

    // 清除并设置模拟数据
    appConfig.fundsInfo.clear();
    appConfig.fundsInfo['000001'] = FundInfo(
      code: '000001',
      name: 'Test Fund 1',
      sector: 'Technology',
      isHeld: true,
      isSpecial: true,
      isPinned: true,
      amount: 1000.0,
      yieldRate: 5.5,
    );
    appConfig.fundsInfo['000002'] = FundInfo(
      code: '000002',
      name: 'Test Fund 2',
      sector: 'Medical',
      isHeld: false,
      isSpecial: false,
      isPinned: false,
      amount: 0.0,
      yieldRate: 0.0,
    );

    appConfig.themeMode = 'Dark';
    appConfig.zhipuApiKey = 'test_key';

    final tempFilePath = '${tempDir.path}/test_backup.json';

    // 1. 仅导出自选列表和特别关注状态
    var success = await appConfig.exportSelectedData(
      destPath: tempFilePath,
      includeFundsList: true,
      includeHoldings: false,
      includeSpecials: true,
      includeStrategies: false,
      includeSettings: false,
    );

    expect(success, true);

    // 验证文件内容
    final file = File(tempFilePath);
    expect(await file.exists(), true);
    final content = await file.readAsString();
    expect(content.contains('Test Fund 1'), true);
    expect(content.contains('Test Fund 2'), true);
    expect(content.contains('1000.0'), false); // holdings 不应该被包含
    expect(content.contains('test_key'), false); // settings 不应该被包含

    // 2. 清除状态并执行合并导入
    appConfig.fundsInfo.clear();
    appConfig.themeMode = 'Light';
    appConfig.zhipuApiKey = '';

    success = await appConfig.importSelectedData(
      tempFilePath,
      includeFundsList: true,
      includeHoldings: false,
      includeSpecials: true,
      includeStrategies: false,
      includeSettings: false,
      isMerge: true,
    );

    expect(success, true);
    expect(appConfig.fundsInfo.length, 2);
    expect(appConfig.fundsInfo['000001']?.isHeld,
        false); // holdings 未被导入，应为默认值 false
    expect(appConfig.fundsInfo['000001']?.isSpecial, true); // specials 被成功导入
    expect(appConfig.themeMode, 'Light'); // settings 未被导入

    // 清理和重置
    appConfig.customConfigPath = null;
    tempDir.deleteSync(recursive: true);
  });

  test('LLM Independent API Key and Persistence test', () async {
    final appConfig = AppConfig();
    final tempDir = Directory.systemTemp.createTempSync();
    appConfig.customConfigPath = '${tempDir.path}/my_funds_test_ocr.json';

    // 预置配置文件（密钥已脱敏，不含任何 API Key 字段）
    final file = File(appConfig.customConfigPath!);
    const jsonContent = '''
    {
      "theme": "Dark",
      "default_ocr_provider": "zhipu"
    }
    ''';
    await file.writeAsString(jsonContent);

    // 清空当前 config 的内存属性
    appConfig.zhipuApiKey = '';
    appConfig.mimoApiKey = '';
    appConfig.customApis = [];

    // 加载配置：密钥存于 SharedPreferences（此处为空 mock），JSON 文件已脱敏
    await appConfig.loadConfig(force: true);

    // 验证脱敏设计：JSON 文件与 SharedPreferences 均无密钥时应保持为空
    expect(appConfig.zhipuApiKey, '');
    expect(appConfig.mimoApiKey, '');
    expect(appConfig.defaultOcrProvider, 'zhipu');

    // 接下来测试使用 updateOcrConfig 批量更新和保存配置
    appConfig.updateOcrConfig(
      provider: 'mimo',
      zhipuKey: 'zhipu-new-key',
      zhipuUrl: 'https://open.bigmodel.cn/api/paas/v4',
      zhipuModelVal: 'glm-ocr',
      mimoKey: 'mimo-new-key',
      mimoUrl: 'https://api.xiaomimimo.com/v1',
      mimoModelVal: 'mimo-v2.5',
      customKey: 'custom-new-key',
      customUrl: 'https://custom-url.com',
      customModelVal: 'custom-model',
    );

    // 验证更新是否成功
    expect(appConfig.defaultOcrProvider, 'mimo');
    expect(appConfig.zhipuApiKey, 'zhipu-new-key');
    expect(appConfig.mimoApiKey, 'mimo-new-key');

    // 确保立即写盘
    await appConfig.saveConfig(forceImmediate: true);

    // 重新加载配置，验证持久化生效
    await appConfig.loadConfig(force: true);
    expect(appConfig.defaultOcrProvider, 'mimo');
    expect(appConfig.zhipuApiKey, 'zhipu-new-key');
    expect(appConfig.mimoApiKey, 'mimo-new-key');

    // 清理和重置
    appConfig.customConfigPath = null;
    tempDir.deleteSync(recursive: true);
  });
}
