import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const MarkdownDesktopApp());
}

// Ctrl+S 快捷键意图。
class SaveIntent extends Intent {
  const SaveIntent();
}

// Ctrl+Shift+S 快捷键意图。
class SaveAsIntent extends Intent {
  const SaveAsIntent();
}

class MarkdownDesktopApp extends StatelessWidget {
  const MarkdownDesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Markdown Desktop',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueGrey,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F6F8),
        appBarTheme: const AppBarTheme(
          elevation: 0.5,
          surfaceTintColor: Colors.transparent,
          backgroundColor: Color(0xFFEFF1F4),
          toolbarHeight: 48,
          titleSpacing: 12,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        useMaterial3: true,
      ),
      home: const MarkdownHomePage(),
    );
  }
}

class MarkdownHomePage extends StatefulWidget {
  const MarkdownHomePage({super.key});

  @override
  State<MarkdownHomePage> createState() => _MarkdownHomePageState();
}

class _MarkdownHomePageState extends State<MarkdownHomePage> {
  // 编辑器内容控制器。
  final TextEditingController _controller = TextEditingController();
  // 本地文件选择允许的 Markdown 扩展。
  final XTypeGroup _mdTypes =
      const XTypeGroup(label: 'Markdown', extensions: ['md', 'markdown', 'txt']);

  String? _currentPath;
  // 是否有未保存的更改。
  bool _dirty = false;
  bool _saving = false;
  String _status = '新建 Markdown';

  @override
  void initState() {
    super.initState();
    _controller.text = '# Markdown 笔记\n\n在左侧编辑，右侧实时预览。';
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    // 文字变化即刻刷新预览，并标记未保存。
    setState(() {
      _dirty = true;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _newFile() async {
    setState(() {
      _controller.clear();
      _currentPath = null;
      _dirty = false;
      _status = '新建 Markdown';
    });
  }

  Future<void> _openFile() async {
    try {
      final XFile? file = await openFile(acceptedTypeGroups: [_mdTypes]);
      if (file == null) return;

      final String? path = file.path;
      if (path == null) {
        _showError('无法读取文件路径');
        return;
      }

      final String content = await file.readAsString();
      setState(() {
        _controller.text = content;
        _currentPath = path;
        _dirty = false;
        _status = '已打开 ${p.basename(path)}';
      });
    } catch (e) {
      _showError('打开失败: $e');
    }
  }

  Future<void> _saveFile({bool saveAs = false}) async {
    if (_saving) return;

    String? targetPath = _currentPath;
    if (saveAs || targetPath == null) {
      final String suggestedName =
          targetPath != null ? p.basename(targetPath) : 'note.md';
      final FileSaveLocation? location = await getSaveLocation(
        acceptedTypeGroups: [_mdTypes],
        suggestedName: suggestedName,
      );

      if (location == null) {
        setState(() {
          _status = '已取消保存';
        });
        return;
      }

      targetPath = location.path;
    }

    // 确定最终保存路径后写入磁盘。
    final String savePath = targetPath;
    setState(() {
      _saving = true;
    });

    try {
      final File file = File(savePath);
      await file.writeAsString(_controller.text);
      setState(() {
        _currentPath = savePath;
        _dirty = false;
        _status = '已保存 ${p.basename(savePath)}';
      });
    } catch (e) {
      _showError('保存失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
    setState(() {
      _status = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final String title = _currentPath != null
        ? '${p.basename(_currentPath!)}${_dirty ? " *" : ''}'
        : 'Markdown 桌面编辑器${_dirty ? " *" : ''}';

    // 全局快捷键包裹，支持 Ctrl+S / Ctrl+Shift+S。
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyS, control: true): SaveIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true):
            SaveAsIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          SaveIntent: CallbackAction<SaveIntent>(onInvoke: (_) {
            _saveFile();
            return null;
          }),
          SaveAsIntent: CallbackAction<SaveAsIntent>(onInvoke: (_) {
            _saveFile(saveAs: true);
            return null;
          }),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              title: Text(title),
              actions: [
                IconButton(
                  tooltip: '新建',
                  icon: const Icon(Icons.note_add_outlined),
                  onPressed: _newFile,
                ),
                IconButton(
                  tooltip: '打开本地 Markdown',
                  icon: const Icon(Icons.folder_open),
                  onPressed: _openFile,
                ),
                IconButton(
                  tooltip: '保存 (Ctrl+S)',
                  icon: const Icon(Icons.save_outlined),
                  onPressed: _saving ? null : () => _saveFile(),
                ),
                IconButton(
                  tooltip: '另存为 (Ctrl+Shift+S)',
                  icon: const Icon(Icons.save_as_outlined),
                  onPressed: _saving ? null : () => _saveFile(saveAs: true),
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(36),
                child: _buildStatusBar(context),
              ),
            ),
            body: _buildWorkspace(context),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBar(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(
            _saving ? Icons.sync : Icons.info_outline,
            size: 16,
            color: colors.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _status,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ),
          if (_currentPath != null) ...[
            const SizedBox(width: 12),
            Text(
              _currentPath!,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWorkspace(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWide = constraints.maxWidth > 900;

        final children = <Widget>[
          Expanded(child: _buildEditor(context)),
          if (isWide)
            VerticalDivider(
              width: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          Expanded(child: _buildPreview(context)),
        ];

        return Flex(
          direction: isWide ? Axis.horizontal : Axis.vertical,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );
      },
    );
  }

  Widget _buildEditor(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFFE9ECEF),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.edit_outlined, color: colors.primary),
              const SizedBox(width: 8),
              Text('Markdown 编辑', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: TextField(
                controller: _controller,
                expands: true,
                maxLines: null,
                minLines: null,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  hintText: '在这里输入 Markdown ...',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFFEFF1F4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.visibility_outlined, color: colors.primary),
              const SizedBox(width: 8),
              Text('实时预览', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Markdown(
                data: _controller.text,
                selectable: true,
                extensionSet: md.ExtensionSet.gitHubFlavored, // 支持表格、列表等 GFM 语法。
                softLineBreak: true, // 单回车即换行。
                padding: const EdgeInsets.all(16),
                onTapLink: (text, href, title) {
                  if (href != null) {
                    _openLink(href);
                  }
                },
                builders: {'u': UnderlineBuilder()},
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                  code: const TextStyle(fontFamily: 'monospace'),
                  codeblockPadding: const EdgeInsets.all(12),
                  blockquoteDecoration: BoxDecoration(
                    color: colors.surfaceVariant.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openLink(String href) async {
    final Uri uri = Uri.parse(href);
    if (!await canLaunchUrl(uri)) {
      _showError('无法打开链接');
      return;
    }

    final bool ok = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!ok) {
      _showError('无法打开链接');
    }
  }
}

/// Renders <u>text</u> as underlined in the preview.
class UnderlineBuilder extends MarkdownElementBuilder {
  UnderlineBuilder();

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) {
    return Text(
      text.text,
      style: (preferredStyle ?? const TextStyle())
          .merge(const TextStyle(decoration: TextDecoration.underline)),
    );
  }
}
