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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        textSelectionTheme: TextSelectionThemeData(
          selectionColor: Colors.blueGrey.withOpacity(0.20),
          selectionHandleColor: Colors.blueGrey,
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
  final XTypeGroup _mdTypes = const XTypeGroup(
    label: 'Markdown',
    extensions: ['md', 'markdown', 'txt'],
  );

  String? _currentPath;
  // 是否有未保存的更改。
  bool _dirty = false;
  bool _saving = false;
  String _status = '新建 Markdown';
  // 当前文件同目录的其他可编辑文件。
  List<String> _siblingFiles = const [];
  // 同目录文件列表是否折叠。
  bool _sidebarCollapsed = false;
  // 编辑 / 预览分隔比例（0-1）。
  double _splitRatio = 0.55;
  // 拖动分隔条时的标记。
  bool _draggingSplit = false;

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
      _siblingFiles = const [];
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

      await _openFileAtPath(path);
    } catch (e) {
      _showError('打开失败: $e');
    }
  }

  Future<void> _openFileAtPath(String path) async {
    try {
      final File f = File(path);
      final String content = await f.readAsString();
      setState(() {
        _controller.text = content;
        _currentPath = path;
        _dirty = false;
        _status = '已打开 ${p.basename(path)}';
      });
      await _refreshSiblingFiles(path);
    } catch (e) {
      _showError('打开失败: $e');
    }
  }

  Future<void> _saveFile({bool saveAs = false}) async {
    if (_saving) return;

    String? targetPath = _currentPath;
    if (saveAs || targetPath == null) {
      final String suggestedName = targetPath != null
          ? p.basename(targetPath)
          : 'note.md';
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
      await _refreshSiblingFiles(savePath);
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
          SaveIntent: CallbackAction<SaveIntent>(
            onInvoke: (_) {
              _saveFile();
              return null;
            },
          ),
          SaveAsIntent: CallbackAction<SaveAsIntent>(
            onInvoke: (_) {
              _saveFile(saveAs: true);
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              title: Row(
                children: [
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
                  const Spacer(),
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              actions: const [],
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

        final double editorFlex = _splitRatio.clamp(0.25, 0.75);
        final double previewFlex = 1 - editorFlex;

        if (!isWide) {
          return Column(
            children: [
              _sidebarCollapsed
                  ? SizedBox(height: 44, child: _buildSidebarToggle(context))
                  : SizedBox(height: 220, child: _buildSidebar(context)),
              Expanded(child: _buildEditor(context)),
              const Divider(height: 1),
              Expanded(child: _buildPreview(context)),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sidebarCollapsed
                ? _buildSidebarToggle(context)
                : SizedBox(width: 240, child: _buildSidebar(context)),
            Expanded(
              flex: (editorFlex * 1000).toInt(),
              child: _buildEditor(context),
            ),
            _buildDragHandle(),
            Expanded(
              flex: (previewFlex * 1000).toInt(),
              child: _buildPreview(context),
            ),
          ],
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
              Text(
                'Markdown 编辑',
                style: Theme.of(context).textTheme.titleMedium,
              ),
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
              child: DefaultSelectionStyle.merge(
                // 强化选中文本高亮，特别是代码块内。
                selectionColor: const Color(0xFFB7D5FF),
                cursorColor: colors.primary,
                child: Markdown(
                  data: _controller.text,
                  selectable: true,
                  extensionSet:
                      md.ExtensionSet.gitHubFlavored, // 支持表格、列表等 GFM 语法。
                  softLineBreak: true, // 单回车即换行。
                  padding: const EdgeInsets.all(16),
                  onTapLink: (text, href, title) {
                    if (href != null) {
                      _openLink(href);
                    }
                  },
                  builders: {'u': UnderlineBuilder()},
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                      .copyWith(
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
          ),
        ],
      ),
    );
  }

  // 编辑/预览的可拖动分隔条（仅宽屏）。
  Widget _buildDragHandle() {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) {
          setState(() => _draggingSplit = true);
        },
        onHorizontalDragEnd: (_) {
          setState(() => _draggingSplit = false);
        },
        onHorizontalDragUpdate: (details) {
          // 根据拖动距离微调比例。
          setState(() {
            _splitRatio = (_splitRatio + details.delta.dx / 800).clamp(
              0.25,
              0.75,
            );
          });
        },
        child: Container(
          width: 12,
          color: _draggingSplit
              ? colors.primary.withOpacity(0.12)
              : colors.outlineVariant.withOpacity(0.4),
          child: Center(
            child: Container(
              width: 2,
              height: 64,
              decoration: BoxDecoration(
                color: colors.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openLink(String href) async {
    final Uri uri = Uri.parse(href);
    if (!await canLaunchUrl(uri)) {
      _showError('无法打开链接');
      return;
    }

    final bool ok = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!ok) {
      _showError('无法打开链接');
    }
  }

  // 列出当前文件所在目录的其他 Markdown/TXT 文件。
  Widget _buildSiblingList(BuildContext context) {
    if (_currentPath == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('打开文件后显示同目录的其他 Markdown/TXT'),
        ),
      );
    }

    if (_siblingFiles.isEmpty) {
      return const Center(child: Text('该目录下暂无其他可编辑文件'));
    }

    return ListView.separated(
      itemCount: _siblingFiles.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final path = _siblingFiles[index];
        final name = p.basename(path);
        final bool isActive = _currentPath == path;
        return ListTile(
          dense: true,
          selected: isActive,
          selectedTileColor: Theme.of(
            context,
          ).colorScheme.primary.withOpacity(0.08),
          title: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          onTap: isActive ? null : () => _openFileAtPath(path),
        );
      },
    );
  }

  // 同目录文件侧边栏。
  Widget _buildSidebar(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.folder_open, color: colors.primary),
              const SizedBox(width: 8),
              const Expanded(child: Text('同目录文件')),
              IconButton(
                tooltip: '折叠',
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  setState(() => _sidebarCollapsed = true);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: _buildSiblingList(context),
            ),
          ),
        ],
      ),
    );
  }

  // 折叠后的侧边栏展开按钮。
  Widget _buildSidebarToggle(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      color: colors.outlineVariant.withOpacity(0.2),
      child: IconButton(
        tooltip: '展开文件列表',
        icon: const Icon(Icons.chevron_right),
        onPressed: () {
          setState(() => _sidebarCollapsed = false);
        },
      ),
    );
  }

  Future<void> _refreshSiblingFiles(String path) async {
    try {
      final Directory dir = Directory(p.dirname(path));
      if (!await dir.exists()) {
        setState(() {
          _siblingFiles = const [];
        });
        return;
      }

      final List<String> entries = await dir
          .list()
          .where((entity) => entity is File)
          .map((entity) => entity.path)
          .where((p) => _isEditableFile(p))
          .toList();

      entries.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      if (mounted) {
        setState(() {
          _siblingFiles = entries;
        });
      }
    } catch (_) {
      // 安静失败，避免打断主流程。
    }
  }

  bool _isEditableFile(String path) {
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    return ['md', 'markdown', 'txt'].contains(ext);
  }
}

/// Renders <u>text</u> as underlined in the preview.
class UnderlineBuilder extends MarkdownElementBuilder {
  UnderlineBuilder();

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) {
    return Text(
      text.text,
      style: (preferredStyle ?? const TextStyle()).merge(
        const TextStyle(decoration: TextDecoration.underline),
      ),
    );
  }
}
