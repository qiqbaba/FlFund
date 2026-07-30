import 'dart:io';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart'
    show Colors, Icons, Material, MaterialType, AdaptiveTextSelectionToolbar;
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'scaled_checkbox.dart';
import 'paste_helper.dart';

import '../../core/config.dart';
import '../../core/fund_provider.dart';
import '../../core/utils/pinyin_search.dart';
import '../../core/utils/ocr_service.dart';

class ImportMyFundsDialog extends StatefulWidget {
  const ImportMyFundsDialog({super.key});

  @override
  State<ImportMyFundsDialog> createState() => _ImportMyFundsDialogState();
}

class _ImportMyFundsDialogState extends State<ImportMyFundsDialog> {
  // 手动输入和 Tab 相关状态
  int _tabIndex = 0;
  FundRegistryItem? _selectedFund;
  late final TextEditingController _manualSearchController;
  List<FundRegistryItem> _searchResults = [];

  // 截图识别相关状态
  String? _selectedImagePath;
  bool _isRecognizing = false;
  bool _isConfigExpanded = false;
  String? _errorMessage;

  late final TextEditingController _apiKeyController;
  late final TextEditingController _apiUrlController;
  late final TextEditingController _modelController;
  late String _selectedProvider;
  List<Map<String, dynamic>> _ocrResults = [];
  final Set<int> _selectedOcrIndices = {};

  late String _zhipuApiKey;
  late String _zhipuApiUrl;
  late String _zhipuModel;

  late String _mimoApiKey;
  late String _mimoApiUrl;
  late String _mimoModel;

  late String _customApiKey;
  late String _customApiUrl;
  late String _customModel;

  void _saveCurrentToTemp(String provider) {
    if (provider == 'zhipu') {
      _zhipuApiKey = _apiKeyController.text.trim();
      _zhipuApiUrl = _apiUrlController.text.trim();
      _zhipuModel = _modelController.text.trim();
    } else if (provider == 'mimo') {
      _mimoApiKey = _apiKeyController.text.trim();
      _mimoApiUrl = _apiUrlController.text.trim();
      _mimoModel = _modelController.text.trim();
    } else if (provider == 'custom') {
      _customApiKey = _apiKeyController.text.trim();
      _customApiUrl = _apiUrlController.text.trim();
      _customModel = _modelController.text.trim();
    } else if (provider.startsWith('custom_')) {
      final appConfig = AppConfig();
      final index = appConfig.customApis.indexWhere((e) => e['id'] == provider);
      if (index != -1) {
        appConfig.customApis[index]['key'] = _apiKeyController.text.trim();
        appConfig.customApis[index]['url'] = _apiUrlController.text.trim();
        appConfig.customApis[index]['model'] = _modelController.text.trim();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    final appConfig = AppConfig();
    _selectedProvider = appConfig.defaultOcrProvider;

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
    _manualSearchController = TextEditingController();
  }

  @override
  void dispose() {
    _manualSearchController.dispose();
    _apiKeyController.dispose();
    _apiUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  // 拾取文件截图
  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'bmp'],
      );
      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedImagePath = result.files.single.path;
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
          '这是一张自选基金列表截图，请帮我从中识别出所有的基金信息。请务必只提取截图中明确写出的信息，杜绝任何联想或脑补。\n\n'
          '针对列表中的每一项基金，识别规则如下：\n'
          '1. 请在截图中寻找6位数字的基金代码（例如：001234）以及对应的基金名称（例如：天弘恒生科技ETF联接C）。\n'
          '2. 将它们分别提取为 code 和 name。\n\n'
          '请仅以JSON格式数组返回，结构如下：[{"code": "xxxxxx", "name": "xxx"}]。\n'
          '如果某项在截图中没有写明基金代码，请将"code"设为空字符串""（但请尽量从截图文字中提取那6位数字作为代码）。\n'
          '只返回这个JSON数组，不要包含任何Markdown标记（如```json）或额外文字说明。';

      final results = await OcrService.recognize(
        imagePath: _selectedImagePath!,
        apiKey: apiKey,
        apiUrl: _apiUrlController.text.trim(),
        model: _modelController.text.trim(),
        prompt: prompt,
      );

      final List<Map<String, dynamic>> processedResults = [];
      final pinyinSearch = PinyinSearch();

      for (var item in results) {
        if (item is Map) {
          String code = item['code']?.toString() ?? '';
          String name = item['name']?.toString() ?? '';

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

          // 不再强行过滤，允许保留未匹配的项，由用户手动修正
          if (code.isNotEmpty &&
              RegExp(r'^\d{6}$').hasMatch(code) &&
              name.isEmpty) {
            final matched = pinyinSearch.search(code);
            if (matched.isNotEmpty) {
              name = matched.first.name;
            }
          }
          processedResults.add({
            'code': code,
            'name': name,
          });
        }
      }

      if (processedResults.isEmpty) {
        throw Exception('未从截图中识别到任何基金信息，请确认截图是否包含清晰的基金列表。');
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
      );

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

  // 保存截图识别到的全部自选勾选项
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
      });
    }

    if (fundsToImport.isNotEmpty) {
      appConfig.addFunds(fundsToImport);
      fundProvider.loadMyFunds();
      fundProvider.refreshAll(); // 静默刷新数据以加载最新估值

      Navigator.pop(context, {
        'status': 'success',
        'message': '导入成功：已成功导入 ${fundsToImport.length} 只自选基金。',
      });
    } else {
      Navigator.pop(context);
    }
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

  // 保存手动添加的自选基金
  void _saveManualAdd(
      BuildContext context, AppConfig appConfig, FundProvider fundProvider) {
    if (_selectedFund == null) return;

    final code = _selectedFund!.code;
    final name = _selectedFund!.name;
    final sector = _selectedFund!.type;

    // 检查是否已经存在
    if (appConfig.fundsInfo.containsKey(code)) {
      _showError('该基金已在自选列表中');
      return;
    }

    final fundsToImport = [
      {
        'code': code,
        'name': name,
        'sector': sector,
      }
    ];

    appConfig.addFunds(fundsToImport);
    fundProvider.loadMyFunds();
    fundProvider.refreshAll();

    Navigator.pop(context, {
      'status': 'success',
      'message': '已成功添加自选基金：$name ($code)',
    });
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

  Widget _buildTabButton(int index, String label, IconData icon, bool isDark) {
    final isSelected = _tabIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _tabIndex = index;
          _errorMessage = null;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? fluent.Colors.blue.withValues(alpha: isDark ? 0.2 : 0.1)
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
                  _buildTabButton(
                      0, '手动输入', Icons.keyboard_alt_rounded, isDark),
                  const SizedBox(width: 16),
                  _buildTabButton(
                      1, '截图识别', Icons.screenshot_monitor_rounded, isDark),
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
                            width: 1.5,
                            style: BorderStyle.solid,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate_rounded,
                                size: 32, color: fluent.Colors.blue),
                            const SizedBox(height: 6),
                            const Text('点击选择基金自选列表截图',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  ScaledCheckbox(
                    checked: appConfig.ocrPreferClassC,
                    onChanged: (val) {
                      if (val != null) {
                        appConfig.updateOcrPreferClassC(val);
                      }
                    },
                    content: const Text(
                      '若基金名称过长截图中未完整显示，匹配时优先选择C类',
                      style: TextStyle(fontSize: 11),
                    ),
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
                                const Text('大模型 API 配置 (截图识别)',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold)),
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
                                  onSecondaryTapDown: (details) {
                                    PasteHelper.showPasteMenu(
                                        context,
                                        details.globalPosition,
                                        _apiKeyController);
                                  },
                                  onLongPressStart: (details) {
                                    PasteHelper.showPasteMenu(
                                        context,
                                        details.globalPosition,
                                        _apiKeyController);
                                  },
                                  child: fluent.TextBox(
                                    controller: _apiKeyController,
                                    placeholder: _selectedProvider == 'zhipu'
                                        ? '输入 智谱GLM API 密钥...'
                                        : _selectedProvider == 'mimo'
                                            ? '输入 小米MIMO API 密钥 (sk-... 或 tp-...)...'
                                            : '输入 API 密钥...',
                                    obscureText: true,
                                    enableInteractiveSelection: true,
                                    suffix: PasteHelper.buildPasteSuffix(
                                        context: context,
                                        controller: _apiKeyController),
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
                          'AI 正在识别自选截图中的基金...',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 6),
                        Text(
                          '正在提取基金名称与代码',
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // 4. 识别结果列表
                  Row(
                    children: [
                      Text(
                          '识别到的基金列表 (共 ${_ocrResults.length} 只，已选 ${_selectedOcrIndices.length} 只，可直接点击修改名称/代码)：',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 11)),
                      const Spacer(),
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
                    height: 240,
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
                                child: fluent.Tooltip(
                                  message: '点击修正基金官方匹配',
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
                                                child: Text(
                                                  item['name'],
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                    decoration: TextDecoration
                                                        .underline,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Icon(
                                                fluent.FluentIcons.edit,
                                                size: 11,
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
                                              fontSize: 11,
                                              color: RegExp(r'^\d{6}$')
                                                      .hasMatch(item['code']
                                                          .toString())
                                                  ? Colors.grey
                                                  : fluent.Colors.orange,
                                              fontWeight: RegExp(r'^\d{6}$')
                                                      .hasMatch(item['code']
                                                          .toString())
                                                  ? FontWeight.normal
                                                  : FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
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
        if (_tabIndex == 0)
          fluent.FilledButton(
            onPressed: _selectedFund != null
                ? () => _saveManualAdd(context, appConfig, fundProvider)
                : null,
            child: const Text('确认添加自选'),
          )
        else if (_ocrResults.isEmpty)
          fluent.FilledButton(
            onPressed: (_selectedImagePath != null && !_isRecognizing)
                ? () => _startImageRecognition(appConfig)
                : null,
            child: const Text('开始智能识别'),
          )
        else
          fluent.FilledButton(
            onPressed: _selectedOcrIndices.isNotEmpty
                ? () => _saveOcrImport(context, appConfig, fundProvider)
                : null,
            child: Text('确认导入自选 (${_selectedOcrIndices.length})'),
          ),
      ],
    );
  }
}
