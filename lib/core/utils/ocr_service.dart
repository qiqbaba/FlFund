import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

class OcrService {
  /// 宽松/截断容错的 JSON 列表解析器
  static List<dynamic> parseLooseJsonList(String content) {
    String jsonText = content.trim();

    // 1. 去除 markdown 代码块包裹
    if (jsonText.startsWith('```')) {
      final lines = jsonText.split('\n');
      if (lines.first.startsWith('```')) {
        lines.removeAt(0);
      }
      if (lines.isNotEmpty && lines.last.startsWith('```')) {
        lines.removeLast();
      }
      jsonText = lines.join('\n').trim();
    }

    // 2. 尝试直接完整解析整个 JSON
    try {
      final decoded = json.decode(jsonText);
      if (decoded is List) {
        return decoded;
      }
      if (decoded is Map) {
        // 如果是一个对象，寻找里面的列表键 (例如 "funds", "list", "data" 等)
        for (var value in decoded.values) {
          if (value is List) {
            return value;
          }
        }
        // 如果找不到任何列表键，但它本身是一个类似基金的对象，包裹成单元素列表
        if (decoded.containsKey('name')) {
          return [decoded];
        }
      }
    } catch (_) {
      // 完整解析失败，进入宽松的逐段/截断修复解析
    }

    // 3. 尝试寻找 '[' 和 ']' 之间的内容进行解析
    final start = jsonText.indexOf('[');
    final end = jsonText.lastIndexOf(']');
    if (start != -1 && end != -1 && end > start) {
      final subText = jsonText.substring(start, end + 1);
      try {
        final decoded = json.decode(subText);
        if (decoded is List) return decoded;
      } catch (_) {}
    }

    // 4. 如果还是失败（可能是截断导致没有闭合的 ']'，或者是以 JSONL 格式返回）
    // 使用“大括号匹配提取”来找出所有形如 {...} 的子串，并对它们分别进行解析
    final List<dynamic> results = [];
    int braceCount = 0;
    int startIndex = -1;

    for (int i = 0; i < jsonText.length; i++) {
      final char = jsonText[i];
      if (char == '{') {
        if (braceCount == 0) {
          startIndex = i;
        }
        braceCount++;
      } else if (char == '}') {
        if (braceCount > 0) {
          braceCount--;
          if (braceCount == 0 && startIndex != -1) {
            final objText = jsonText.substring(startIndex, i + 1);
            try {
              final decodedObj = json.decode(objText);
              if (decodedObj is Map) {
                results.add(decodedObj);
              }
            } catch (_) {
              // 这一块损坏，忽略
            }
            startIndex = -1;
          }
        }
      }
    }

    // 5. 如果在大模型截断时，连一个完整的对象都没提取到，而且包含 '['，尝试强行补齐 ']'
    if (results.isEmpty && start != -1) {
      try {
        final repairedText = '${jsonText.substring(start).trim()}]';
        final repairedTextClean =
            repairedText.replaceAll(RegExp(r',\s*\]$'), ']');
        final decoded = json.decode(repairedTextClean);
        if (decoded is List) return decoded;
      } catch (_) {}
    }

    return results;
  }

  /// 封装包含网络重试、代理旁路的 Dio 实例创建
  static Dio _createDio(String requestUrl) {
    final dio = Dio();
    dio.options.connectTimeout = const Duration(seconds: 35);
    dio.options.receiveTimeout = const Duration(seconds: 70);

    // 对已知国内 AI 服务域名自动强制直连，避免被境外代理 IP 导致的风控和连接重置问题
    final lowerUrl = requestUrl.toLowerCase();
    final isChinaAi =
        lowerUrl.contains('bigmodel.cn') || lowerUrl.contains('xiaomimimo.com');

    if (!kIsWeb && isChinaAi) {
      debugPrint('[ProxyBypass] 启用强制直连 (DIRECT) 绕过系统代理');
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.findProxy = (uri) => 'DIRECT';
          return client;
        },
      );
    }
    return dio;
  }

  /// 封装重试机制的 POST 请求
  static Future<Response> _postWithRetry(
    Dio dio,
    String url, {
    required Map<String, dynamic> headers,
    required dynamic data,
    int maxRetries = 3,
  }) async {
    Response? response;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        response = await dio.post(
          url,
          options: Options(headers: headers),
          data: data,
        );
        return response;
      } catch (e) {
        final isRetryable = e is DioException &&
            e.error is SocketException &&
            e.error.toString().contains('10054');
        if (isRetryable && attempt < maxRetries) {
          debugPrint(
              '[OcrService重试] 第 $attempt 次请求因连接重置失败，${1 << attempt} 秒后重试...');
          await Future.delayed(Duration(seconds: 1 << attempt));
          continue;
        }
        rethrow;
      }
    }
    throw Exception('请求失败且超出最大重试次数');
  }

  /// 发起多模态 OCR 识别，并返回解析后的 JSON 列表结果
  static Future<List<dynamic>> recognize({
    required String imagePath,
    required String apiKey,
    required String apiUrl,
    required String model,
    required String prompt,
  }) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      throw Exception('图片文件不存在');
    }
    final originalBytes = await file.readAsBytes();
    final base64Image = base64Encode(originalBytes);

    String mimeType = 'image/jpeg';
    if (imagePath.toLowerCase().endsWith('.png')) {
      mimeType = 'image/png';
    }

    final isGlmOcr = model.toLowerCase() == 'glm-ocr';
    final dio = _createDio(apiUrl);

    if (isGlmOcr) {
      // ========== 两阶段识别架构 (GLM-OCR) ==========
      debugPrint('[OcrService] 启动两阶段 GLM-OCR 识别流程...');

      // 1. 第一阶段：OCR 版面识别 (获取 Markdown 文本)
      String ocrUrl = apiUrl;
      if (ocrUrl.endsWith('/chat/completions')) {
        ocrUrl =
            ocrUrl.substring(0, ocrUrl.length - '/chat/completions'.length);
      }
      if (ocrUrl.endsWith('/')) {
        ocrUrl = '${ocrUrl}layout_parsing';
      } else {
        ocrUrl = '$ocrUrl/layout_parsing';
      }

      final Map<String, dynamic> ocrRequestData = {
        'model': 'glm-ocr',
        'file': 'data:$mimeType;base64,$base64Image',
      };

      debugPrint('[OcrService] Step 1: 发起 OCR 版面识别请求 -> $ocrUrl');
      final ocrResponse = await _postWithRetry(
        dio,
        ocrUrl,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        data: ocrRequestData,
      );

      if (ocrResponse.statusCode != 200) {
        throw Exception('OCR 识别失败，状态码: ${ocrResponse.statusCode}');
      }

      final result = ocrResponse.data['result'];
      String ocrText = '';
      if (result != null) {
        if (result is Map) {
          ocrText = result['text']?.toString() ?? '';
        } else {
          ocrText = result.toString();
        }
      }

      debugPrint('[OcrService] OCR 识别文本长度: ${ocrText.length} 字符');
      if (ocrText.trim().isEmpty) {
        throw Exception('OCR 未能识别出图片中的任何文本内容');
      }

      // 2. 第二阶段：结构化 JSON 抽取
      String chatUrl = apiUrl;
      if (!chatUrl.endsWith('/chat/completions')) {
        if (chatUrl.endsWith('/')) {
          chatUrl = '${chatUrl}chat/completions';
        } else {
          chatUrl = '$chatUrl/chat/completions';
        }
      }

      const String chatModel = 'glm-4-flash';
      final Map<String, dynamic> chatRequestData = {
        'model': chatModel,
        'messages': [
          {
            'role': 'user',
            'content': prompt,
          },
          {
            'role': 'user',
            'content': ocrText,
          }
        ],
        'response_format': {'type': 'json_object'},
        'max_tokens': 4096,
      };

      debugPrint(
          '[OcrService] Step 2: 发起大模型结构化提取请求 -> $chatUrl, 使用模型: $chatModel');
      final chatResponse = await _postWithRetry(
        dio,
        chatUrl,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        data: chatRequestData,
      );

      if (chatResponse.statusCode != 200) {
        throw Exception('两阶段结构化提取失败，状态码: ${chatResponse.statusCode}');
      }

      final content = chatResponse.data['choices'][0]['message']['content']
              ?.toString()
              .trim() ??
          '';
      return parseLooseJsonList(content);
    } else {
      // ========== 一阶段多模态识别流程 ==========
      debugPrint('[OcrService] 启动一阶段多模态看图识别流程...');

      String chatUrl = apiUrl;
      if (!chatUrl.endsWith('/chat/completions')) {
        if (chatUrl.endsWith('/')) {
          chatUrl = '${chatUrl}chat/completions';
        } else {
          chatUrl = '$chatUrl/chat/completions';
        }
      }

      final Map<String, dynamic> requestData = {
        'model': model,
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text': prompt,
              },
              {
                'type': 'image_url',
                'image_url': {'url': 'data:$mimeType;base64,$base64Image'}
              }
            ]
          }
        ],
        'max_tokens': 4096,
      };

      if (chatUrl.contains('bigmodel.cn') ||
          chatUrl.contains('api.openai.com') ||
          chatUrl.contains('deepseek.com') ||
          chatUrl.contains('xiaomimimo.com')) {
        requestData['response_format'] = {'type': 'json_object'};
      }

      if (model.toLowerCase().contains('deepseek')) {
        requestData['thinking'] = {'type': 'disabled'};
      }

      final chatResponse = await _postWithRetry(
        dio,
        chatUrl,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        data: requestData,
      );

      if (chatResponse.statusCode != 200) {
        throw Exception('多模态接口识别失败，状态码: ${chatResponse.statusCode}');
      }

      final content = chatResponse.data['choices'][0]['message']['content']
              ?.toString()
              .trim() ??
          '';
      return parseLooseJsonList(content);
    }
  }

  /// 统一解析 API 报错信息
  static String parseApiError(dynamic e) {
    if (e is DioException) {
      final response = e.response;
      if (response != null) {
        final statusCode = response.statusCode;
        String? apiMessage;

        try {
          if (response.data is Map) {
            final errorObj = response.data['error'];
            if (errorObj is Map) {
              apiMessage = errorObj['message']?.toString();
            }
          } else if (response.data is String) {
            final data = jsonDecode(response.data);
            if (data is Map && data['error'] is Map) {
              apiMessage = data['error']['message']?.toString();
            }
          }
        } catch (_) {}

        final detail = apiMessage != null ? '\n错误详情: $apiMessage' : '';

        switch (statusCode) {
          case 400:
            return '请求格式错误 (400)。请检查选用的模型是否正确或图片是否损坏。$detail';
          case 401:
            return 'API 密钥无效 (401)。请检查您输入的 API Key 是否正确。$detail';
          case 402:
            return '账户余额不足 (402)。您的账户余额或额度已耗尽，请前往官方平台充值。$detail';
          case 422:
            return '请求参数错误或内容违规 (422)。$detail';
          case 429:
            return '接口请求频率过快或服务器繁忙 (429)。请稍后再试。$detail';
          case 500:
            return '接口服务内部错误 (500)。请稍后重试。$detail';
          case 503:
            return '服务不可用 (503)。服务器当前超载或正在维护。$detail';
          default:
            return '接口请求失败 (状态码: $statusCode)。$detail';
        }
      }

      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return '网络请求超时。请检查您的网络状况或代理配置。';
      }
      final errStr = e.toString();
      if (errStr.contains('10054') ||
          errStr.contains('10061') ||
          errStr.contains('SocketException')) {
        return '网络请求异常: ${e.message ?? e.toString()}\n\n提示：若您开启了网络代理，可能是因为代理服务器连接异常导致报错。您可以尝试在下方的「大模型 API 配置」中勾选「绕过系统代理直连大模型」后重试，或检查您的代理软件状态。';
      }
      return '网络请求异常: ${e.message ?? e.toString()}';
    }
    return e.toString().replaceAll('Exception:', '');
  }
}
