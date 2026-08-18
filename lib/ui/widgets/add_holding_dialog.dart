import 'dart:io';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart'
    show Colors, Icons, Material, MaterialType, AdaptiveTextSelectionToolbar;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'scaled_checkbox.dart';
import 'paste_helper.dart';

import '../../core/config.dart';
import '../../core/fund_provider.dart';
import '../../core/utils/pinyin_search.dart';
import '../../core/utils/ocr_service.dart';
import '../../core/utils/number_formatter.dart';

class AddHoldingDialog extends StatefulWidget {
  const AddHoldingDialog({super.key});

  @override
  State<AddHoldingDialog> createState() => _AddHoldingDialogState();
}

class _AddHoldingDialogState extends State<AddHoldingDialog> {
  int _tabIndex = 0; // 0: 手动输入, 1: 截图识别

  // 手动输入相关状态
  final TextEditingController _manualSearchController = TextEditingController();
  List<FundRegistryItem> _searchResults = [];
  FundRegistryItem? _selectedFund;
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _yieldController = TextEditingController();

  // 截图识别相关状态
  String? _selectedImagePath;
  bool _isRecognizing = false;
  bool _isConfigExpanded = false;
  String? _errorMessage;
  String _selectedProvider = 'zhipu';

  late TextEditingController _apiKeyController;
  late TextEditingController _apiUrlController;
  late TextEditingController _modelController;

  List<Map<String, dynamic>> _ocrResults = [];
  final Set<int> _selectedOcrIndices = {};
  final List<TextEditingController> _ocrAmountControllers = [];
  final List<TextEditingController> _ocrYieldControllers = [];

  bool _autoSliceLongImage = false;

  late String _zhipuApiKey;
  late String _zhipuApiUrl;
  late String _zhipuModel;

  late String _mimoApiKey;
  late String _mimoApiUrl;
  late String _mimoModel;

  late String _customApiKey;
  late String _customApiUrl;
  late String _customModel;

  void _saveCurrentToTemp(String provider, {bool persist = true}) {
    final appConfig = AppConfig();
    final key = _apiKeyController.text.trim();
    final url = _apiUrlController.text.trim();
    final model = _modelController.text.trim();

    if (provider == 'zhipu') {
      _zhipuApiKey = key;
      _zhipuApiUrl = url;
      _zhipuModel = model;
    } else if (provider == 'mimo') {
      _mimoApiKey = key;
      _mimoApiUrl = url;
      _mimoModel = model;
    } else if (provider == 'custom') {
      _customApiKey = key;
      _customApiUrl = url;
      _customModel = model;
    } else if (provider.startsWith('custom_')) {
      final index = appConfig.customApis.indexWhere((e) => e['id'] == provider);
      if (index != -1) {
        appConfig.customApis[index]['key'] = key;
        appConfig.customApis[index]['url'] = url;
        appConfig.customApis[index]['model'] = model;
      }
    }

    if (persist) {
      appConfig.updateOcrConfig(
        provider: provider,
        zhipuKey: _zhipuApiKey,
        zhipuUrl: _zhipuApiUrl,
        zhipuModelVal: _zhipuModel,
        mimoKey: _mimoApiKey,
        mimoUrl: _mimoApiUrl,
        mimoModelVal: _mimoModel,
        customKey: provider.startsWith('custom_') ? key : _customApiKey,
        customUrl: provider.startsWith('custom_') ? url : _customApiUrl,
        customModelVal: provider.startsWith('custom_') ? model : _customModel,
        autoSliceLongImage: _autoSliceLongImage,
      );
    }
  }

  String _getProviderDisplayName(AppConfig appConfig, String provider) {
    if (provider == 'zhipu') {
      final model = _zhipuModel.isNotEmpty ? _zhipuModel : 'glm-4.6v-flash';
      return '智谱GLM ($model)';
    } else if (provider == 'mimo') {
      final model = _mimoModel.isNotEmpty ? _mimoModel : 'mimo-v2.5';
      return '小米MIMO ($model)';
    } else if (provider == 'custom') {
      final model = _customModel.isNotEmpty ? _customModel : '自定义';
      return '自定义 ($model)';
    } else if (provider.startsWith('custom_')) {
      final item = appConfig.customApis
          .firstWhere((e) => e['id'] == provider, orElse: () => {});
      if (item.isNotEmpty) {
        return item['name'] ?? item['model'] ?? '自定义 API';
      }
      return '自定义 API';
    }
    return provider;
  }

  @override
  void initState() {
    super.initState();
    final appConfig = AppConfig();
    _selectedProvider = appConfig.defaultOcrProvider;
    _autoSliceLongImage = appConfig.ocrAutoSliceLongImage;

    _zhipuApiKey = appConfig.zhipuApiKey;
    _zhipuApiUrl = appConfig.zhipuApiUrl;
    _zhipuModel = appConfig.zhipuModel;

    _mimoApiKey = appConfig.mimoApiKey;
    _mimoApiUrl = appConfig.mimoApiUrl;
    _mimoModel = appConfig.mimoModel;

    _customApiKey = '';
    _customApiUrl = '';
    _customModel = '';

    String initialKey = '';
    String initialUrl = '';
    String initialModel = '';

    if (_selectedProvider == 'zhipu') {
      initialKey = _zhipuApiKey;
      initialUrl = _zhipuApiUrl.isEmpty
          ? 'https://open.bigmodel.cn/api/paas/v4'
          : _zhipuApiUrl;
      initialModel = _zhipuModel.isEmpty ? 'glm-4.6v-flash' : _zhipuModel;
    } else if (_selectedProvider == 'mimo') {
      initialKey = _mimoApiKey;
      initialUrl =
          _mimoApiUrl.isEmpty ? 'https://api.xiaomimimo.com/v1' : _mimoApiUrl;
      initialModel = _mimoModel.isEmpty ? 'mimo-v2.5' : _mimoModel;
    } else if (_selectedProvider.startsWith('custom_')) {
      final item = appConfig.customApis
          .firstWhere((e) => e['id'] == _selectedProvider, orElse: () => {});
      if (item.isNotEmpty) {
        _customApiKey = item['key'] ?? '';
        _customApiUrl = item['url'] ?? '';
        _customModel = item['model'] ?? '';
      }
      initialKey = _customApiKey;
      initialUrl = _customApiUrl;
      initialModel = _customModel;
    } else {
      initialKey = _customApiKey;
      initialUrl = _customApiUrl;
      initialModel = _customModel;
    }

    _apiKeyController = TextEditingController(text: initialKey);
    _apiUrlController = TextEditingController(text: initialUrl);
    _modelController = TextEditingController(text: initialModel);
  }

  @override
  void dispose() {
    _manualSearchController.dispose();
    _amountController.dispose();
    _yieldController.dispose();
    _apiKeyController.dispose();
    _apiUrlController.dispose();
    _modelController.dispose();
    for (var controller in _ocrAmountControllers) {
      controller.dispose();
    }
    for (var controller in _ocrYieldControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  // 联想搜索过滤字典
  void _onSearchChanged(String query) {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }
    final results = PinyinSearch().search(query);
    setState(() {
      _searchResults = results;
    });
  }

  // 拾取文件截图
  Future<void> _pickImage() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'bmp'],
      );
      if (file != null && file.path != null) {
        setState(() {
          _selectedImagePath = file.path;
          _ocrResults = []; // 清理旧数据
          _errorMessage = null;
        });
      }
    } catch (e) {
      _showError('打开文件选择器失败: $e');
    }
  }

  void _showError(String msg) {
    setState(() {
      _errorMessage = msg;
    });
  }

  // 发起多模态识别
  Future<void> _startImageRecognition(AppConfig appConfig) async {
    if (_selectedImagePath == null) {
      _showError('请先选择截图图片。');
      return;
    }

    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      _showError('请输入 API 密钥。');
      return;
    }

    setState(() {
      _isRecognizing = true;
      _errorMessage = null;
      _ocrResults = [];
    });

    try {
      const prompt =
          '这是一张基金持仓截图，请帮我从中识别出持有的所有基金信息。请务必只提取截图中明确写出的信息，杜绝任何联想或脑补。\n\n'
          '识别规则与字段映射如下：\n'
          '1. 第一列为基金名称（如“天弘恒生科技ETF联接C”），映射为 "name"。\n'
          '2. 第二列为“金额/昨日收益”，上面那行数字代表该基金的【持有金额/当前资产】（如 9,440.66），我们需要提取这行数字并去除千分位逗号，映射为 "amount" (如 9440.66)。\n'
          '3. 收益或收益率列的识别：\n'
          '   a. 寻找带百分号的【持有收益率/持仓收益率】（如 -9.24% 或 +18.74%），必须去除百分号%和正号+，映射为 "yield_rate" (如 -9.24 或 18.74)。若截图中无收益率显示，请设为 0.0 或 null。\n'
          '   b. 寻找表示【持有收益/当前收益/累计收益】的金额数值（如 -123.45 或 +500.00），必须去除正号+和人民币/元符号及逗号，映射为 "holding_profit" (如 -123.45 或 500.00)。若截图中无持有收益金额显示，请设为 0.0 或 null。\n\n'
          '请仅以JSON格式数组返回，结构如下：[{"code": "xxxxxx", "name": "xxx", "amount": 123.45, "yield_rate": -1.2, "holding_profit": 50.0}]。\n'
          '如果某项在截图中没有写明基金代码，请务必将"code"设为空字符串""。\n'
          '如果某项没有识别到amount、yield_rate或holding_profit请设为0.0或null，名称设为实际名称。\n'
          '只返回这个JSON数组，不要包含任何Markdown标记（如```json）或额外文字说明。';

      // 保存 API 配置，以免因网络或识别失败而丢失用户输入的 API 密钥
      _saveCurrentToTemp(_selectedProvider, persist: true);

      final results = await OcrService.recognize(
        imagePath: _selectedImagePath!,
        apiKey: apiKey,
        apiUrl: _apiUrlController.text.trim(),
        model: _modelController.text.trim(),
        prompt: prompt,
        autoSliceLongImage: _autoSliceLongImage,
      );

      final List<Map<String, dynamic>> processedResults = [];
      final pinyinSearch = PinyinSearch();

      for (var item in results) {
        if (item is Map) {
          String code = item['code']?.toString() ?? '';
          String name = item['name']?.toString() ?? '';

          // 鲁棒处理：清洗金额字段中的逗号，再进行解析
          final amountStr =
              (item['amount']?.toString() ?? '').replaceAll(',', '').trim();
          final amount = double.tryParse(amountStr) ?? 0.0;

          // 鲁棒处理：清洗收益率字段中的百分号、正号等，再进行解析
          final yieldStr = (item['yield_rate']?.toString() ?? '')
              .replaceAll('%', '')
              .replaceAll('+', '')
              .trim();
          double yieldRate = double.tryParse(yieldStr) ?? 0.0;

          // 鲁棒处理：清洗持有收益金额字段中的正号、货币符号及逗号，再进行解析
          final profitStr = (item['holding_profit']?.toString() ?? '')
              .replaceAll('+', '')
              .replaceAll('￥', '')
              .replaceAll('元', '')
              .replaceAll(',', '')
              .trim();
          final holdingProfit = double.tryParse(profitStr) ?? 0.0;

          // 如果识别出的收益率是0（或未识别到），但持有收益不为0，则通过持有收益和持有金额换算收益率
          if (yieldRate == 0.0 && holdingProfit != 0.0 && amount > 0.0) {
            final cost = amount - holdingProfit;
            if (cost > 0.0) {
              yieldRate = (holdingProfit / cost) * 100.0;
            } else {
              yieldRate = (holdingProfit / amount) * 100.0;
            }
          }

          // 若代码为空但名称不为空，尝试通过本地字典模糊搜索匹配代码
          if (code.isEmpty && name.isNotEmpty) {
            final matched = pinyinSearch.matchFundByName(name,
                preferClassC: appConfig.ocrPreferClassC);
            if (matched != null) {
              code = matched.code;
              name = matched.name; // 用官方标准的基金名字修正
              debugPrint(
                  '[本地字典匹配] 成功模糊匹配到官方标准基金: ${matched.code} - ${matched.name}');
            } else {
              debugPrint('[本地字典匹配] 模糊匹配失败: "$name"');
            }
          }

          processedResults.add({
            'code': code,
            'name': name,
            'amount': amount,
            'yield_rate': yieldRate,
          });
        }
      }

      if (processedResults.isEmpty) {
        throw Exception('未从截图中识别到任何基金信息，请确认截图是否包含清晰的基金持仓。');
      }

      // 保存 API 配置，以免下次重复录入
      _saveCurrentToTemp(_selectedProvider);
      appConfig.updateOcrConfig(
        provider: _selectedProvider,
        zhipuKey: _zhipuApiKey,
        zhipuUrl: _zhipuApiUrl,
        zhipuModelVal: _zhipuModel,
        mimoKey: _mimoApiKey,
        mimoUrl: _mimoApiUrl,
        mimoModelVal: _mimoModel,
        customKey: _customApiKey,
        customUrl: _customApiUrl,
        customModelVal: _customModel,
        autoSliceLongImage: _autoSliceLongImage,
      );

      // 重新分配 Text Controllers
      for (var controller in _ocrAmountControllers) {
        controller.dispose();
      }
      for (var controller in _ocrYieldControllers) {
        controller.dispose();
      }
      _ocrAmountControllers.clear();
      _ocrYieldControllers.clear();

      for (var item in processedResults) {
        _ocrAmountControllers.add(TextEditingController(
            text: (item['amount'] as num).toThousand(precision: 2)));
        _ocrYieldControllers.add(TextEditingController(
            text: (item['yield_rate'] as num).toThousand(precision: 2)));
      }

      setState(() {
        _ocrResults = processedResults;
        _selectedOcrIndices.clear();
        for (int i = 0; i < processedResults.length; i++) {
          _selectedOcrIndices.add(i); // 默认全选
        }
        _isRecognizing = false;
        _selectedProvider = appConfig.defaultOcrProvider;
      });
    } catch (e) {
      debugPrint('图片识别失败: $e');
      final errorMsg = OcrService.parseApiError(e);
      _showError('识别失败: $errorMsg');
      setState(() {
        _isRecognizing = false;
      });
    }
  }

  // 保存手动输入的持仓
  void _saveManualInput(
      BuildContext context, AppConfig appConfig, FundProvider fundProvider) {
    if (_selectedFund == null) return;

    final code = _selectedFund!.code;
    final name = _selectedFund!.name;
    final sector = _selectedFund!.type;

    final amount =
        double.tryParse(_amountController.text.replaceAll(',', '')) ?? 0.0;
    final yieldRate =
        double.tryParse(_yieldController.text.replaceAll(',', '')) ?? 0.0;

    appConfig.addFund(code, name, sector);
    appConfig.updateHoldInfo(code, true, amount, yieldRate);

    // 重新加载并更新数据
    fundProvider.loadMyFunds();
    fundProvider.refreshAll(isForce: true);

    Navigator.pop(context, {
      'status': 'success',
      'message': '添加持仓成功：已保存 $name ($code) 的持有信息。',
    });
  }

  // 保存截图识别到的全部勾选项
  void _saveOcrImport(
      BuildContext context, AppConfig appConfig, FundProvider fundProvider) {
    if (_selectedOcrIndices.isEmpty) return;

    // 检查是否有勾选的项未匹配到有效的 6 位代码
    for (int idx in _selectedOcrIndices) {
      final item = _ocrResults[idx];
      final code = item['code']?.toString() ?? '';
      if (code.isEmpty || !RegExp(r'^\d{6}$').hasMatch(code)) {
        _showError(
            '存在未成功匹配有效6位基金代码的已勾选项（如“${item['name']}”）。请先点击该项进行修正，或取消勾选该项后再导入。');
        return;
      }
    }

    final pinyinSearch = PinyinSearch();
    final List<Map<String, dynamic>> fundsToImport = [];

    for (int idx in _selectedOcrIndices) {
      final item = _ocrResults[idx];
      final code = item['code'];
      final originalName = item['name'];

      final amount = double.tryParse(
              _ocrAmountControllers[idx].text.replaceAll(',', '')) ??
          0.0;
      final yieldRate =
          double.tryParse(_ocrYieldControllers[idx].text.replaceAll(',', '')) ??
              0.0;

      String name = originalName;
      String sector = '其它';

      // 先到字典里找更准确的官方名称与类型分类
      final searchResults = pinyinSearch.search(code);
      if (searchResults.isNotEmpty) {
        final matched = searchResults.firstWhere((r) => r.code == code,
            orElse: () => searchResults.first);
        name = matched.name;
        sector = matched.type;
      }

      fundsToImport.add({
        'code': code,
        'name': name,
        'sector': sector,
        'amount': amount,
        'yield_rate': yieldRate,
        'is_held': true,
      });
    }

    if (fundsToImport.isNotEmpty) {
      appConfig.addFundsAndHoldInfos(fundsToImport);
      fundProvider.loadMyFunds();
      fundProvider.refreshAll(isForce: true);

      Navigator.pop(context, {
        'status': 'success',
        'message': '导入成功：已导入 ${fundsToImport.length} 只基金的持仓数据。',
      });
    } else {
      Navigator.pop(context);
    }
  }

  void _showEditFundDialog(BuildContext context, int index) {
    final searchController = TextEditingController();
    List<FundRegistryItem> localSearchResults = [];

    fluent.showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setStateDialog) {
            return fluent.ContentDialog(
              constraints: const BoxConstraints(maxWidth: 400, maxHeight: 380),
              title: Row(
                children: [
                  Icon(fluent.FluentIcons.edit,
                      size: 18, color: fluent.Colors.blue),
                  const SizedBox(width: 8),
                  const Text('修正基金匹配',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
              content: Container(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '当前匹配: ${_ocrResults[index]['name']}',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '代码: ${_ocrResults[index]['code']}',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      const Text('搜索目标官方基金',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 11)),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: fluent.AutoSuggestBox<FundRegistryItem>(
                          controller: searchController,
                          items: localSearchResults.map((item) {
                            final label =
                                '${item.code} - ${item.name} (${item.type})';
                            return fluent.AutoSuggestBoxItem<FundRegistryItem>(
                              value: item,
                              label: label,
                              onSelected: () {
                                // 在主 State 中更新该项数据
                                setState(() {
                                  _ocrResults[index]['code'] = item.code;
                                  _ocrResults[index]['name'] = item.name;
                                });
                                Navigator.pop(dialogContext);
                              },
                              child: fluent.Tooltip(
                                message: label,
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (text, reason) {
                            if (text.isEmpty) {
                              setStateDialog(() {
                                localSearchResults = [];
                              });
                              return;
                            }
                            final results = PinyinSearch().search(text);
                            setStateDialog(() {
                              localSearchResults = results;
                            });
                          },
                          placeholder: '输入基金代码、拼音或中文...',
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
              actions: [
                fluent.Button(
                  child: const Text('取消'),
                  onPressed: () => Navigator.pop(dialogContext),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTabButton(int index, String label, IconData icon) {
    final isSelected = _tabIndex == index;
    final isDark = fluent.FluentTheme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () {
        setState(() {
          _tabIndex = index;
          _errorMessage = null;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
                  ? fluent.Colors.blue.withValues(alpha: 0.2)
                  : fluent.Colors.blue.withValues(alpha: 0.1))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? fluent.Colors.blue
                : (isDark ? Colors.white12 : Colors.black12),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: isSelected
                    ? fluent.Colors.blue
                    : (isDark ? Colors.white70 : Colors.black87)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? fluent.Colors.blue
                    : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final fundProvider = Provider.of<FundProvider>(context, listen: false);
    final isDark = fluent.FluentTheme.of(context).brightness == Brightness.dark;

    return fluent.ContentDialog(
      constraints: const BoxConstraints(maxWidth: 500, maxHeight: 620),
      content: Container(
        padding: const EdgeInsets.only(top: 8),
        constraints: const BoxConstraints(maxHeight: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Tab Header
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildTabButton(0, '手动输入', Icons.keyboard_alt_rounded),
                  const SizedBox(width: 16),
                  _buildTabButton(1, '截图识别', Icons.screenshot_monitor_rounded),
                ],
              ),
              const SizedBox(height: 20),

              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: fluent.InfoBar(
                    title: const Text('错误提示'),
                    content: Text(_errorMessage!),
                    severity: fluent.InfoBarSeverity.error,
                    onClose: () {
                      setState(() {
                        _errorMessage = null;
                      });
                    },
                  ),
                ),

              // TAB 0: 手动输入
              if (_tabIndex == 0) ...[
                if (_selectedFund == null) ...[
                  const Text('1. 搜索并选择基金',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: fluent.AutoSuggestBox<FundRegistryItem>(
                      controller: _manualSearchController,
                      items: _searchResults.map((item) {
                        final label =
                            '${item.code} - ${item.name} (${item.type})';
                        return fluent.AutoSuggestBoxItem<FundRegistryItem>(
                          value: item,
                          label: label,
                          onSelected: () {
                            setState(() {
                              _selectedFund = item;
                              _manualSearchController.clear();
                              _searchResults = [];
                            });
                          },
                          child: fluent.Tooltip(
                            message: label,
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (text, reason) {
                        _onSearchChanged(text);
                      },
                      placeholder: '输入基金代码、拼音或中文...',
                      trailingIcon: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.0),
                        child: Icon(Icons.search, size: 16, color: Colors.grey),
                      ),
                    ),
                  ),
                  const SizedBox(height: 60),
                ] else ...[
                  // 选中的基金卡片
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.04)
                          : Colors.black.withValues(alpha: 0.02),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: isDark ? Colors.white10 : Colors.black12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedFund!.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '代码: ${_selectedFund!.code}  |  分类: ${_selectedFund!.type}',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        fluent.IconButton(
                          icon: const Icon(Icons.close_rounded,
                              size: 16, color: Colors.grey),
                          onPressed: () {
                            setState(() {
                              _selectedFund = null;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('2. 填写持仓数据',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 12),
                  const Text('持有金额 (元)', style: TextStyle(fontSize: 11)),
                  const SizedBox(height: 6),
                  fluent.TextBox(
                    controller: _amountController,
                    placeholder: '输入持有本金，例如: 10,000.00',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^[0-9,]*\.?[0-9]{0,2}')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('持有收益率 (%)', style: TextStyle(fontSize: 11)),
                  const SizedBox(height: 6),
                  fluent.TextBox(
                    controller: _yieldController,
                    placeholder: '输入持仓收益率，例如: 5.5 (代表 5.5%)',
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^-?[0-9,]*\.?[0-9]{0,4}')),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ],

              // TAB 1: 截图识别
              if (_tabIndex == 1) ...[
                if (_ocrResults.isEmpty && !_isRecognizing) ...[
                  // 1. 文件拾取区域
                  if (_selectedImagePath != null) ...[
                    Container(
                      height: 110,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.02)
                            : Colors.black.withValues(alpha: 0.02),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: isDark ? Colors.white10 : Colors.black12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(
                          File(_selectedImagePath!),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: fluent.Button(
                        onPressed: _pickImage,
                        child:
                            const Text('重新选择', style: TextStyle(fontSize: 11)),
                      ),
                    ),
                  ] else ...[
                    GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        height: 110,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.02)
                              : Colors.black.withValues(alpha: 0.01),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDark ? Colors.white24 : Colors.black26,
                            width: 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate_rounded,
                                size: 32, color: fluent.Colors.blue),
                            const SizedBox(height: 6),
                            const Text('点击选择基金持仓截图',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),

                  // 识别与匹配控制按钮 (置顶排在最前)
                  Row(
                    children: [
                      Expanded(
                        child: ScaledCheckbox(
                          checked: appConfig.ocrPreferClassC,
                          onChanged: (val) {
                            if (val != null) {
                              appConfig.updateOcrPreferClassC(val);
                            }
                          },
                          content: const Text(
                            '若名称不全优先选C类',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          fluent.ToggleSwitch(
                            checked: _autoSliceLongImage,
                            onChanged: (v) {
                              setState(() {
                                _autoSliceLongImage = v;
                              });
                            },
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            '智能切分超长截图',
                            style: TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 2. 折叠 API 配置
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.black.withValues(alpha: 0.05)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            setState(() {
                              _isConfigExpanded = !_isConfigExpanded;
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            child: Row(
                              children: [
                                Icon(Icons.settings_rounded,
                                    size: 14,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black54),
                                const SizedBox(width: 6),
                                const Text('大模型 API 配置',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: fluent.Colors.blue.withValues(
                                          alpha: isDark ? 0.18 : 0.08),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: fluent.Colors.blue.withValues(
                                            alpha: isDark ? 0.35 : 0.25),
                                      ),
                                    ),
                                    child: Text(
                                      _getProviderDisplayName(
                                          appConfig, _selectedProvider),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: fluent.Colors.blue,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Icon(
                                  _isConfigExpanded
                                      ? Icons.expand_less_rounded
                                      : Icons.expand_more_rounded,
                                  size: 16,
                                  color: Colors.grey,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_isConfigExpanded) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: fluent.Divider(),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('API 提供商',
                                    style: TextStyle(fontSize: 10)),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Expanded(
                                      child: fluent.ComboBox<String>(
                                        value: ([
                                          'zhipu',
                                          'mimo',
                                          'custom',
                                          ...appConfig.customApis
                                              .map((item) => item['id']!)
                                        ].contains(_selectedProvider))
                                            ? _selectedProvider
                                            : 'zhipu',
                                        items: [
                                          fluent.ComboBoxItem(
                                            value: 'zhipu',
                                            child: Text('智谱GLM',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: isDark
                                                        ? Colors.white
                                                        : Colors.black87)),
                                          ),
                                          fluent.ComboBoxItem(
                                            value: 'mimo',
                                            child: Text('小米MIMO',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: isDark
                                                        ? Colors.white
                                                        : Colors.black87)),
                                          ),
                                          fluent.ComboBoxItem(
                                            value: 'custom',
                                            child: Text('自定义 (新建)',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: isDark
                                                        ? Colors.white
                                                        : Colors.black87)),
                                          ),
                                          ...appConfig.customApis.map((item) {
                                            return fluent.ComboBoxItem(
                                              value: item['id']!,
                                              child: Text(
                                                  item['name'] ?? '自定义 API',
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      color: isDark
                                                          ? Colors.white
                                                          : Colors.black87)),
                                            );
                                          }),
                                        ],
                                        onChanged: (val) {
                                          if (val != null &&
                                              val != _selectedProvider) {
                                            _saveCurrentToTemp(
                                                _selectedProvider);
                                            setState(() {
                                              _selectedProvider = val;
                                              if (val == 'zhipu') {
                                                _apiKeyController.text =
                                                    _zhipuApiKey;
                                                _apiUrlController
                                                    .text = _zhipuApiUrl
                                                        .isEmpty
                                                    ? 'https://open.bigmodel.cn/api/paas/v4'
                                                    : _zhipuApiUrl;
                                                _modelController.text =
                                                    _zhipuModel.isEmpty
                                                        ? 'glm-4.6v-flash'
                                                        : _zhipuModel;
                                              } else if (val == 'mimo') {
                                                _apiKeyController.text =
                                                    _mimoApiKey;
                                                _apiUrlController
                                                    .text = _mimoApiUrl
                                                        .isEmpty
                                                    ? 'https://api.xiaomimimo.com/v1'
                                                    : _mimoApiUrl;
                                                _modelController.text =
                                                    _mimoModel.isEmpty
                                                        ? 'mimo-v2.5'
                                                        : _mimoModel;
                                              } else if (val
                                                  .startsWith('custom_')) {
                                                final item = appConfig
                                                    .customApis
                                                    .firstWhere(
                                                        (e) => e['id'] == val,
                                                        orElse: () => {});
                                                if (item.isNotEmpty) {
                                                  _apiKeyController.text =
                                                      item['key'] ?? '';
                                                  _apiUrlController.text =
                                                      item['url'] ?? '';
                                                  _modelController.text =
                                                      item['model'] ?? '';
                                                }
                                              } else {
                                                _apiKeyController.text =
                                                    _customApiKey;
                                                _apiUrlController.text =
                                                    _customApiUrl;
                                                _modelController.text =
                                                    _customModel;
                                              }
                                            });
                                          }
                                        },
                                      ),
                                    ),
                                    if (_selectedProvider
                                        .startsWith('custom_')) ...[
                                      const SizedBox(width: 8),
                                      fluent.IconButton(
                                        icon: const Icon(
                                            Icons.delete_outline_rounded,
                                            color: Colors.redAccent,
                                            size: 16),
                                        onPressed: () {
                                          final toDelete = _selectedProvider;
                                          setState(() {
                                            _selectedProvider = 'zhipu';
                                            _apiKeyController.text =
                                                _zhipuApiKey;
                                            _apiUrlController
                                                .text = _zhipuApiUrl
                                                    .isEmpty
                                                ? 'https://open.bigmodel.cn/api/paas/v4'
                                                : _zhipuApiUrl;
                                            _modelController.text =
                                                _zhipuModel.isEmpty
                                                    ? 'glm-4.6v-flash'
                                                    : _zhipuModel;
                                          });
                                          appConfig.deleteCustomApi(toDelete);
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 8),
                                const Text('API Key (密钥)',
                                    style: TextStyle(fontSize: 10)),
                                const SizedBox(height: 4),
                                GestureDetector(
                                  onSecondaryTapDown: (details) =>
                                      PasteHelper.showPasteMenu(
                                          context,
                                          details.globalPosition,
                                          _apiKeyController),
                                  onLongPressStart: (details) =>
                                      PasteHelper.showPasteMenu(
                                          context,
                                          details.globalPosition,
                                          _apiKeyController),
                                  child: fluent.TextBox(
                                    suffix: PasteHelper.buildPasteSuffix(
                                        context: context,
                                        controller: _apiKeyController),
                                    controller: _apiKeyController,
                                    placeholder: _selectedProvider == 'zhipu'
                                        ? '输入 智谱GLM API 密钥...'
                                        : _selectedProvider == 'mimo'
                                            ? '输入 小米MIMO API 密钥 (sk-... 或 tp-...)...'
                                            : '输入 API 密钥...',
                                    obscureText: true,
                                    enableInteractiveSelection: true,
                                    contextMenuBuilder:
                                        (context, editableTextState) {
                                      return Material(
                                        type: MaterialType.transparency,
                                        child: AdaptiveTextSelectionToolbar
                                            .buttonItems(
                                          anchors: editableTextState
                                              .contextMenuAnchors,
                                          buttonItems: [
                                            ContextMenuButtonItem(
                                              onPressed: () {
                                                editableTextState.pasteText(
                                                    SelectionChangedCause
                                                        .toolbar);
                                              },
                                              type: ContextMenuButtonType.paste,
                                              label: '粘贴',
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text('Base URL (接口地址)',
                                    style: TextStyle(fontSize: 10)),
                                const SizedBox(height: 4),
                                fluent.TextBox(
                                  controller: _apiUrlController,
                                  placeholder:
                                      '例如: https://open.bigmodel.cn/api/paas/v4',
                                  readOnly: _selectedProvider != 'custom' &&
                                      !_selectedProvider.startsWith('custom_'),
                                ),
                                const SizedBox(height: 8),
                                const Text('Model (模型名称，需支持 Vision 输入)',
                                    style: TextStyle(fontSize: 10)),
                                const SizedBox(height: 4),
                                fluent.TextBox(
                                  controller: _modelController,
                                  placeholder: '例如: glm-4.6v-flash',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ] else if (_isRecognizing) ...[
                  // 3. 正在识别中
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        fluent.ProgressRing(),
                        SizedBox(height: 16),
                        Text(
                          'AI 正在识别截图中持有的基金...',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 6),
                        Text(
                          '正在提取代码、本金及收益率',
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // 4. 识别结果列表
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '识别到的持仓列表 (共 ${_ocrResults.length} 只，已选 ${_selectedOcrIndices.length} 只，勾选导入并可直接修改)：',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      fluent.Button(
                        child:
                            const Text('重选截图', style: TextStyle(fontSize: 10)),
                        onPressed: () {
                          setState(() {
                            _ocrResults = [];
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 260,
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: isDark ? Colors.white10 : Colors.black12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: _ocrResults.length,
                      separatorBuilder: (context, index) =>
                          const fluent.Divider(),
                      itemBuilder: (context, index) {
                        final item = _ocrResults[index];
                        final isSelected = _selectedOcrIndices.contains(index);

                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              ScaledCheckbox(
                                checked: isSelected,
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      _selectedOcrIndices.add(index);
                                    } else {
                                      _selectedOcrIndices.remove(index);
                                    }
                                  });
                                },
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 3,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () =>
                                      _showEditFundDialog(context, index),
                                  child: MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: fluent.Tooltip(
                                                message: item['name'],
                                                child: Text(
                                                  item['name'],
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 11,
                                                    decoration: TextDecoration
                                                        .underline,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Icon(
                                              fluent.FluentIcons.edit,
                                              size: 10,
                                              color: fluent.Colors.grey
                                                  .withValues(alpha: 0.8),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          item['code'].toString().isEmpty
                                              ? '代码: 未匹配 (点击修正)'
                                              : (RegExp(r'^\d{6}$').hasMatch(
                                                      item['code'].toString())
                                                  ? '代码: ${item['code']}'
                                                  : '代码: ${item['code']} (格式不符，点击修正)'),
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: RegExp(r'^\d{6}$').hasMatch(
                                                    item['code'].toString())
                                                ? Colors.grey
                                                : fluent.Colors.orange,
                                            fontWeight: RegExp(r'^\d{6}$')
                                                    .hasMatch(
                                                        item['code'].toString())
                                                ? FontWeight.normal
                                                : FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // 金额输入
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('本金(元)',
                                        style: TextStyle(
                                            fontSize: 9, color: Colors.grey)),
                                    const SizedBox(height: 2),
                                    SizedBox(
                                      height: 24,
                                      child: fluent.TextBox(
                                        controller:
                                            _ocrAmountControllers[index],
                                        placeholder: '金额',
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(
                                              RegExp(r'^[0-9,]*\.?[0-9]{0,2}')),
                                        ],
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              // 收益率输入
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('收益率(%)',
                                        style: TextStyle(
                                            fontSize: 9, color: Colors.grey)),
                                    const SizedBox(height: 2),
                                    SizedBox(
                                      height: 24,
                                      child: fluent.TextBox(
                                        controller: _ocrYieldControllers[index],
                                        placeholder: '收益率',
                                        keyboardType: const TextInputType
                                            .numberWithOptions(
                                            decimal: true, signed: true),
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(
                                              RegExp(
                                                  r'^-?[0-9,]*\.?[0-9]{0,4}')),
                                        ],
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        fluent.Button(
          child: const Text('取消'),
          onPressed: () => Navigator.pop(context),
        ),

        // 渲染不同的主行动按钮
        if (_tabIndex == 0) // 手动输入
          fluent.FilledButton(
            onPressed: _selectedFund != null
                ? () => _saveManualInput(context, appConfig, fundProvider)
                : null,
            child: const Text('保存持仓'),
          )
        else if (_ocrResults.isEmpty) // 截图识别 - 待识别
          fluent.FilledButton(
            onPressed: (_selectedImagePath != null && !_isRecognizing)
                ? () => _startImageRecognition(appConfig)
                : null,
            child: const Text('开始智能识别'),
          )
        else // 截图识别 - 待导入
          fluent.FilledButton(
            onPressed: _selectedOcrIndices.isNotEmpty
                ? () => _saveOcrImport(context, appConfig, fundProvider)
                : null,
            child: Text('确认导入选中持仓 (${_selectedOcrIndices.length})'),
          ),
      ],
    );
  }
}
