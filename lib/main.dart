import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart' as m;
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    minimumSize: Size(800, 600),
    center: true,
    title: 'Markdown 桌面编辑器',
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
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

class MarkdownDesktopApp extends StatefulWidget {
  const MarkdownDesktopApp({super.key});

  @override
  State<MarkdownDesktopApp> createState() => _MarkdownDesktopAppState();
}

class _MarkdownDesktopAppState extends State<MarkdownDesktopApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.light
          ? ThemeMode.dark
          : ThemeMode.light;
    });
  }

  FluentThemeData _buildLightTheme() {
    return FluentThemeData(
      brightness: Brightness.light,
      accentColor: Colors.blue,
      visualDensity: VisualDensity.compact,
      scaffoldBackgroundColor: const Color(0xFFF4F6F8),
    );
  }

  FluentThemeData _buildDarkTheme() {
    return FluentThemeData(
      brightness: Brightness.dark,
      accentColor: Colors.blue,
      visualDensity: VisualDensity.compact,
      scaffoldBackgroundColor: const Color(0xFF0F1419),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      debugShowCheckedModeBanner: false,
      title: 'Markdown Desktop',
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      themeMode: _themeMode,
      home: MarkdownHomePage(
        themeMode: _themeMode,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}

class MarkdownHomePage extends StatefulWidget {
  const MarkdownHomePage({
    super.key,
    required this.themeMode,
    required this.onToggleTheme,
  });

  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;

  @override
  State<MarkdownHomePage> createState() => _MarkdownHomePageState();
}

class _MarkdownHomePageState extends State<MarkdownHomePage> with WindowListener {
  // 编辑器内容控制器。
  final TextEditingController _controller = TextEditingController();
  // 本地文件选择允许的 Markdown 扩展。
  final XTypeGroup _mdTypes = const XTypeGroup(
    label: 'Markdown',
    extensions: ['md', 'markdown', 'txt'],
  );

  String? _currentPath;
  String _lastSavedContent = '';
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

  String get _windowTitle => _currentPath != null
      ? '${p.basename(_currentPath!)}${_dirty ? " *" : ''}'
      : 'Markdown 桌面编辑器${_dirty ? " *" : ''}';

  @override
  void initState() {
    super.initState();
    _controller.text = '# Markdown 笔记\n\n在左侧编辑，右侧实时预览。';
    _lastSavedContent = _controller.text;
    _controller.addListener(_onTextChanged);
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
  }

  bool get _isDark => widget.themeMode == ThemeMode.dark;

  void _onTextChanged() {
    final String current = _controller.text;
    final bool dirtyNow = current != _lastSavedContent;
    if (dirtyNow != _dirty) {
      setState(() {
        _dirty = dirtyNow;
      });
      _updateWindowTitle();
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Future<void> onWindowClose() async {
    final shouldClose = await _confirmClose();
    if (shouldClose) {
      // 先取消拦截再正常关闭，避免卡死
      await windowManager.setPreventClose(false);
      await windowManager.close();
    }
  }

  Future<void> _newFile() async {
    if (_dirty) {
      final bool proceed = await _confirmDirtyBeforeAction('创建新文件');
      if (!proceed) return;
    }
    setState(() {
      _controller.clear();
      _currentPath = null;
      _dirty = false;
      _status = '新建 Markdown';
      _siblingFiles = const [];
      _lastSavedContent = _controller.text;
    });
    _updateWindowTitle();
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

      if (_dirty && path != _currentPath) {
        final bool proceed = await _confirmDirtyBeforeAction('打开其他文件');
        if (!proceed) return;
      }

      await _openFileAtPath(path);
    } catch (e) {
      _showError('打开失败: $e');
    }
  }

  Future<void> _openFileAtPath(String path) async {
    if (_dirty && path != _currentPath) {
      final bool proceed = await _confirmDirtyBeforeAction('切换文件');
      if (!proceed) return;
    }
    try {
      final File f = File(path);
      final String content = await f.readAsString();
      setState(() {
        _controller.text = content;
        _currentPath = path;
        _dirty = false;
        _status = '已打开 ${p.basename(path)}';
        _lastSavedContent = content;
      });
      await _refreshSiblingFiles(path);
      _updateWindowTitle();
    } catch (e) {
      _showError('打开失败: $e');
    }
  }

  Future<bool> _saveFile({bool saveAs = false}) async {
    if (_saving) return false;

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
        return false;
      }

      targetPath = location.path;
    }

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
        _lastSavedContent = _controller.text;
      });
      await _refreshSiblingFiles(savePath);
      _updateWindowTitle();
      return true;
    } catch (e) {
      _showError('保存失败: $e');
      return false;
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
    setState(() {
      _status = message;
    });
  }

  Future<bool> _confirmClose() async {
    if (!_dirty) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => ContentDialog(
        title: const Text('有未保存的更改'),
        content: const Text('退出前要保存当前文件吗？'),
        actions: [
          Button(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          Button(
            child: const Text('不保存'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
          FilledButton(
            child: const Text('保存并退出'),
            onPressed: () async {
              final ok = await _saveFile();
              Navigator.pop(ctx, ok);
            },
          ),
        ],
      ),
    );

    return result ?? false;
  }

  Future<bool> _confirmDirtyBeforeAction(String actionLabel) async {
    if (!_dirty) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => ContentDialog(
        title: Text('有未保存的更改'),
        content: Text('$actionLabel 前是否保存当前文件？'),
        actions: [
          Button(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          Button(
            child: const Text('不保存'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
          FilledButton(
            child: const Text('保存并继续'),
            onPressed: () async {
              final ok = await _saveFile();
              Navigator.pop(ctx, ok);
            },
          ),
        ],
      ),
    );

    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final String title = _windowTitle;

    return WillPopScope(
      onWillPop: _confirmClose,
      child: Shortcuts(
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
          child: NavigationView(
            content: ScaffoldPage(
              padding: EdgeInsets.zero,
              header: _buildCommandBar(context),
              content: _buildWorkspace(context),
              bottomBar: _buildStatusBar(context),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _updateWindowTitle() async {
    try {
      await windowManager.setTitle(_windowTitle);
    } catch (_) {
      // 忽略窗口 API 错误，避免影响编辑体验。
    }
  }

  Widget _buildCommandBar(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.micaBackgroundColor,
        border: Border(
          bottom: BorderSide(color: theme.resources.surfaceStrokeColorDefault),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Expanded(
            child: CommandBar(
              mainAxisAlignment: MainAxisAlignment.start,
              overflowBehavior: CommandBarOverflowBehavior.dynamicOverflow,
              primaryItems: [
                CommandBarButton(
                  icon: const Icon(FluentIcons.add),
                  label: const Text('新建'),
                  onPressed: _newFile,
                ),
                CommandBarButton(
                  icon: const Icon(FluentIcons.folder_open),
                  label: const Text('打开'),
                  onPressed: _openFile,
                ),
                CommandBarButton(
                  icon: const Icon(FluentIcons.save),
                  label: const Text('保存  Ctrl+S'),
                  onPressed: _saving ? null : () => _saveFile(),
                ),
                CommandBarButton(
                  icon: const Icon(FluentIcons.save_as),
                  label: const Text('另存为  Ctrl+Shift+S'),
                  onPressed: _saving ? null : () => _saveFile(saveAs: true),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: ToggleSwitch(
              checked: _isDark,
              content: Text(_isDark ? '暗色' : '浅色'),
              onChanged: (_) => widget.onToggleTheme(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(BuildContext context) {
    final colors = FluentTheme.of(context);
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.micaBackgroundColor,
        border: Border(
          top: BorderSide(color: colors.resources.surfaceStrokeColorDefault),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _saving ? FluentIcons.sync : FluentIcons.info,
            size: 16,
            color: colors.accentColor,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(_status, overflow: TextOverflow.ellipsis)),
          if (_currentPath != null) ...[
            const SizedBox(width: 12),
            Text(
              _currentPath!,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
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
              Expanded(
                child: Container(
                  color: FluentTheme.of(context).micaBackgroundColor,
                  child: Column(
                    children: [
                      Expanded(child: _buildEditor(context)),
                      const Divider(size: 1),
                      Expanded(child: _buildPreview(context)),
                    ],
                  ),
                ),
              ),
            ],
          );
        }

        final double sidebarWidth = _sidebarCollapsed ? 44 : 240;
        final double handleWidth = 12;
        final double availableWidth =
            (constraints.maxWidth - sidebarWidth - handleWidth).clamp(
              300,
              constraints.maxWidth,
            );

    final theme = FluentTheme.of(context);
    final mica = theme.micaBackgroundColor;
    return Container(
      color: mica,
      child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sidebarCollapsed
                  ? _buildSidebarToggle(context)
                  : SizedBox(width: 240, child: _buildSidebar(context)),
              Expanded(
                flex: (editorFlex * 1000).toInt(),
                child: _buildEditor(context),
              ),
              _buildDragHandle(availableWidth),
              Expanded(
                flex: (previewFlex * 1000).toInt(),
                child: _buildPreview(context),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSidebar(BuildContext context) {
    final colors = FluentTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.micaBackgroundColor,
        border: Border(
          right: BorderSide(color: colors.resources.surfaceStrokeColorDefault),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(FluentIcons.folder_open, color: colors.accentColor),
              const SizedBox(width: 8),
              const Expanded(child: Text('同目录文件')),
              IconButton(
                icon: const Icon(FluentIcons.chevron_left),
                onPressed: () => setState(() => _sidebarCollapsed = true),
                style: ButtonStyle(
                  padding: ButtonState.all(const EdgeInsets.all(4)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: colors.cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colors.resources.surfaceStrokeColorDefault,
                ),
              ),
              child: _buildSiblingList(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarToggle(BuildContext context) {
    final colors = FluentTheme.of(context);
    return Container(
      width: 44,
      color: colors.micaBackgroundColor,
      child: IconButton(
        icon: const Icon(FluentIcons.chevron_right),
        onPressed: () => setState(() => _sidebarCollapsed = false),
      ),
    );
  }

  Widget _buildEditor(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
    color: theme.micaBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(FluentIcons.edit, color: theme.accentColor),
              const SizedBox(width: 8),
              const Text('Markdown 编辑'),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.resources.surfaceStrokeColorDefault,
                ),
              ),
              child: TextBox(
                controller: _controller,
                expands: true,
                maxLines: null,
                minLines: null,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(fontFamily: 'monospace'),
                highlightColor: Colors.transparent,
                unfocusedColor: Colors.transparent,
                decoration: WidgetStateProperty.resolveWith(
                  (states) => const BoxDecoration(
                    border: Border.fromBorderSide(
                      BorderSide(color: Colors.transparent, width: 0),
                    ),
                    color: Colors.transparent,
                  ),
                ),
                padding: const EdgeInsets.all(16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
    final theme = FluentTheme.of(context);
    // 为 Markdown 提供一份 Material 风格的主题，确保组件样式一致。
    final baseTextTheme = m.ThemeData(
      brightness: _isDark ? Brightness.dark : Brightness.light,
      useMaterial3: true,
    ).textTheme;
    final m.TextTheme safeTextTheme = baseTextTheme.copyWith(
      bodyMedium: (baseTextTheme.bodyMedium ?? const m.TextStyle()).copyWith(
        fontSize: baseTextTheme.bodyMedium?.fontSize ?? 14,
      ),
    );
    final materialTheme = m.ThemeData(
      colorScheme: m.ColorScheme.fromSeed(
        seedColor: theme.accentColor,
        brightness: _isDark ? Brightness.dark : Brightness.light,
      ),
      textTheme: safeTextTheme,
      useMaterial3: true,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      color: theme.micaBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(FluentIcons.view, color: theme.accentColor),
              const SizedBox(width: 8),
              const Text('实时预览'),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.resources.surfaceStrokeColorDefault,
                ),
              ),
              child: DefaultSelectionStyle.merge(
                // 强化选中文本高亮，特别是代码块内。
                selectionColor: const Color(0xFFB7D5FF),
                cursorColor: theme.accentColor,
                child: m.Theme(
                  data: materialTheme,
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
                    styleSheet: MarkdownStyleSheet.fromTheme(materialTheme)
                        .copyWith(
                          code: const TextStyle(fontFamily: 'monospace'),
                          codeblockPadding: const EdgeInsets.all(12),
                          blockquoteDecoration: BoxDecoration(
                            color: theme.micaBackgroundColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
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
  Widget _buildDragHandle(double availableWidth) {
    final theme = FluentTheme.of(context);
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
            _splitRatio = (_splitRatio + details.delta.dx / availableWidth)
                .clamp(0.25, 0.75);
          });
        },
        child: Container(
          width: 12,
          color: _draggingSplit
              ? theme.accentColor.withOpacity(0.12)
              : theme.resources.surfaceStrokeColorDefault,
          child: Center(
            child: Container(
              width: 2,
              height: 64,
              decoration: BoxDecoration(
                color: theme.resources.controlStrokeColorSecondary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
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
      separatorBuilder: (_, __) => const Divider(size: 1),
      itemBuilder: (context, index) {
        final path = _siblingFiles[index];
        final name = p.basename(path);
        final bool isActive = _currentPath == path;
        return ListTile.selectable(
          selected: isActive,
          selectionMode: ListTileSelectionMode.single,
          leading: const Icon(FluentIcons.page_header),
          title: Text(name, overflow: TextOverflow.ellipsis),
          onPressed: isActive ? null : () => _openFileAtPath(path),
        );
      },
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
