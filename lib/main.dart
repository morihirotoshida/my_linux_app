import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:xterm/xterm.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
      ),
      home: const MyCustomUI(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class FuncKeyIntent extends Intent {
  final String label;
  const FuncKeyIntent(this.label);
}

class MyCustomUI extends StatefulWidget {
  const MyCustomUI({super.key});

  @override
  State<MyCustomUI> createState() => _MyCustomUIState();
}

class _MyCustomUIState extends State<MyCustomUI> {
  final GlobalKey<PopupMenuButtonState<String>> _menuKey = GlobalKey();
  final FocusNode _menuFocusNode = FocusNode();

  String _lastPressed = "キーボードの矢印キーで移動できます";
  String _currentSelection = "";

  final List<Map<String, dynamic>> _openWindows = [];
  static const double _buttonHeight = 32.0;

  void _openTerminalWindow() {
    Terminal terminal = Terminal();
    Pty pty = Pty.start(
      'bash',
      arguments: ['-l'],
      environment: Platform.environment,
      workingDirectory: Platform.environment['HOME'],
      columns: 80,
      rows: 24,
    );

    FocusNode terminalFocus = FocusNode();

    terminalFocus.addListener(() {
      if (mounted) setState(() {});
    });

    pty.output.listen((data) {
      terminal.write(utf8.decode(data, allowMalformed: true));
    });
    terminal.onOutput = (data) {
      pty.write(Uint8List.fromList(utf8.encode(data)));
    };

    pty.exitCode.then((code) {
      if (mounted) {
        setState(() {
          _openWindows.removeWhere((win) => win['pty'] == pty);
        });
      }
    });

    setState(() {
      _openWindows.add({
        'id': DateTime.now().toString(),
        'title': 'ターミナル (bash)',
        'terminal': terminal,
        'pty': pty,
        'focusNode': terminalFocus,
        'x': 50.0 + (_openWindows.length * 20),
        'y': 50.0 + (_openWindows.length * 20),
        'width': 500.0,
        'height': 350.0,
        'isMaximized': true, // 最初から最大化された状態で起動
        'isMinimized': false,
      });
    });
  }

  // ★ 誤って消えてしまっていたウィンドウ制御ボタンの描画メソッド（復旧）
  Widget _buildWindowControlButton(IconData icon, double orderValue, VoidCallback onPressed, {Color? defaultBgColor}) {
    return FocusTraversalOrder(
      order: NumericFocusOrder(orderValue),
      child: Padding(
        padding: const EdgeInsets.only(left: 4.0),
        child: SizedBox(
          width: 28,
          height: 24,
          child: ElevatedButton(
            onPressed: onPressed,
            style: ButtonStyle(
              backgroundColor: MaterialStateProperty.resolveWith<Color>((states) {
                if (states.contains(MaterialState.focused)) return Colors.yellow;
                return defaultBgColor ?? Colors.grey[700]!;
              }),
              foregroundColor: MaterialStateProperty.resolveWith<Color>((states) {
                if (states.contains(MaterialState.focused)) return Colors.black;
                return Colors.white;
              }),
              padding: MaterialStateProperty.all(EdgeInsets.zero),
              shape: MaterialStateProperty.all(const RoundedRectangleBorder()),
            ),
            child: Icon(icon, size: 16),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingWindow(int index, BoxConstraints constraints) {
    var win = _openWindows[index];
    bool isMinimized = win['isMinimized'];
    bool isMaximized = win['isMaximized'];
    double baseOrder = (index + 1) * 10.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: Colors.grey[600]!, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(5, 5))],
      ),
      child: Column(
        children: [
          // タイトルバー
          GestureDetector(
            onPanUpdate: isMaximized ? null : (details) {
              setState(() {
                win['x'] += details.delta.dx; win['y'] += details.delta.dy;
              });
            },
            child: Container(
              color: Colors.blue[900],
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              height: 30,
              child: Row(
                children: [
                  Expanded(
                    child: Text(win['title'], style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                  ),
                  _buildWindowControlButton(Icons.remove, baseOrder + 0.1, () {
                    setState(() => win['isMinimized'] = !isMinimized);
                  }),
                  _buildWindowControlButton(isMaximized ? Icons.filter_none : Icons.crop_square, baseOrder + 0.2, () {
                    setState(() {
                      win['isMaximized'] = !isMaximized;
                    });
                  }),
                  _buildWindowControlButton(Icons.close, baseOrder + 0.3, () {
                    setState(() {
                      if (win['pty'] != null) (win['pty'] as Pty).kill();
                      _openWindows.removeAt(index);
                    });
                  }, defaultBgColor: Colors.red[700]),
                ],
              ),
            ),
          ),
          // コンテンツ部分
          if (!isMinimized)
            Expanded(
              child: FocusTraversalOrder(
                order: NumericFocusOrder(baseOrder + 0.4),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: (win['focusNode'] as FocusNode).hasFocus ? Colors.yellow : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    child: TerminalView(
                      win['terminal'], 
                      focusNode: win['focusNode'],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _handleAction(String label) {
    setState(() {
      _lastPressed = "$label が押されました";
      _currentSelection = label;
    });

    if (label == 'ESC') {
      _menuFocusNode.requestFocus();
      setState(() => _lastPressed = "ESC: メニューバーにフォーカスを戻しました");
    }
  }

  void _handleShowMenu() {
    // ★ マウスでクリックされた時も、強制的に「Menu」を選択状態（黄色い丸）にする
    setState(() {
      _currentSelection = "Menu";
    });

    final RenderBox renderBox = _menuKey.currentContext?.findRenderObject() as RenderBox;
    final Offset offset = renderBox.localToGlobal(Offset.zero);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(offset.dx, offset.dy - 320, offset.dx + renderBox.size.width, offset.dy),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey[700]!, width: 1)),
      items: [
        const PopupMenuItem(value: 'exit', child: ListTile(leading: Icon(Icons.exit_to_app, color: Colors.red, size: 20), title: Text('終了', style: TextStyle(color: Colors.red)), dense: true)),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'sys_info', child: ListTile(leading: Icon(Icons.computer, size: 20), title: Text('システム情報 (uname)'), dense: true)),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'refresh', child: ListTile(leading: Icon(Icons.refresh, size: 20), title: Text('情報の更新'), dense: true)),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'maximize', child: ListTile(leading: Icon(Icons.fullscreen, size: 20), title: Text('ウインドウの最大化/復元'), dense: true)),
        const PopupMenuItem(value: 'terminal', child: ListTile(leading: Icon(Icons.terminal, size: 20), title: Text('ターミナル'), dense: true)),
      ],
    ).then((value) {
      if (value != null) _handleMenuAction(value);
      // メニューが閉じられたら選択状態を解除（黄色い丸を消す）
      setState(() => _currentSelection = "");
    });
  }

  void _handleMenuAction(String value) {
    setState(() => _currentSelection = "");
    switch (value) {
      case 'maximize':
        windowManager.isMaximized().then((isMaximized) {
          if (isMaximized) {
            windowManager.unmaximize();
            setState(() => _lastPressed = "アプリのウインドウを元のサイズに戻しました");
          } else {
            windowManager.maximize();
            setState(() => _lastPressed = "アプリのウインドウを最大化しました");
          }
        });
        break;
      case 'terminal': 
        _openTerminalWindow(); 
        break;
      case 'refresh': 
        setState(() => _lastPressed = "情報を更新しました"); 
        break;
      case 'sys_info':
        Process.run('uname', ['-a']).then((result) => setState(() => _lastPressed = "System: ${result.stdout}"));
        break;
      case 'exit': 
        exit(0);
    }
  }

// ★ ESCボタンのみ角丸に戻したキーボタン描画メソッド
  Widget _buildKeyButton(String label, double orderValue, {Color? defaultColor}) {
    bool isSelected = _currentSelection == label;
    bool isEsc = label == "ESC";

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.0),
        child: FocusTraversalOrder(
          order: NumericFocusOrder(orderValue),
          child: SizedBox(
            height: _buttonHeight,
            child: ElevatedButton(
              onFocusChange: (hasFocus) {
                if (hasFocus) setState(() { _currentSelection = label; _lastPressed = "$label にフォーカス中"; });
              },
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: (isSelected && !isEsc) ? Colors.yellow : (defaultColor ?? Colors.grey[800]),
                foregroundColor: (isSelected && !isEsc) ? Colors.black : Colors.white,
                // ★ ここを変更：ESCの時だけ全角丸、それ以外は上部を直角にする
                shape: RoundedRectangleBorder(
                  borderRadius: isEsc 
                      ? BorderRadius.circular(4) // ESCの場合は四隅すべて角丸
                      : const BorderRadius.only(   // それ以外（F1〜F12）は上部のみ直角
                          topLeft: Radius.zero,
                          topRight: Radius.zero,
                          bottomLeft: Radius.circular(4),
                          bottomRight: Radius.circular(4),
                        ),
                ),
              ),
              onPressed: () => _handleAction(label),
              child: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        LogicalKeySet(LogicalKeyboardKey.escape): const FuncKeyIntent('ESC'),
        for (var i = 1; i <= 12; i++) LogicalKeySet(LogicalKeyboardKey(0x110000000 + i)): FuncKeyIntent('F$i'),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          FuncKeyIntent: CallbackAction<FuncKeyIntent>(onInvoke: (intent) => _handleAction(intent.label)),
        },
        child: Scaffold(
          body: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      border: Border.all(color: Colors.grey[700]!, width: 2),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return Stack(
                          children: [
                            Center(child: Text(_lastPressed, style: const TextStyle(fontSize: 18, color: Colors.greenAccent, fontFamily: 'monospace'))),
                            for (int i = 0; i < _openWindows.length; i++)
                              Positioned(
                                left: _openWindows[i]['isMaximized'] ? 0 : _openWindows[i]['x'],
                                top: _openWindows[i]['isMaximized'] ? 0 : _openWindows[i]['y'],
                                width: _openWindows[i]['isMaximized'] ? constraints.maxWidth : _openWindows[i]['width'],
                                height: _openWindows[i]['isMinimized'] ? 34.0 : (_openWindows[i]['isMaximized'] ? constraints.maxHeight : _openWindows[i]['height']),
                                child: _buildFloatingWindow(i, constraints),
                              ),
                          ],
                        );
                      }
                    ),
                  ),
                ),
                Container(
                  color: Colors.black87,
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                  child: Row(
                    children: [
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(1.0),
                        child: SizedBox(
                          width: _buttonHeight,
                          height: _buttonHeight,
                          child: Focus(
                            focusNode: _menuFocusNode,
                            onKeyEvent: (node, event) {
                              if (event is KeyDownEvent && (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.space)) {
                                _handleShowMenu(); return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
                            onFocusChange: (hasFocus) {
                              if (hasFocus) setState(() => _currentSelection = "Menu");
                            },
                            child: GestureDetector(
                              onTap: _handleShowMenu,
                              child: Container(
                                key: _menuKey,
                                decoration: BoxDecoration(
                                  color: _currentSelection == "Menu" ? Colors.yellow : Colors.transparent,
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(child: Icon(Icons.square, color: Colors.white, size: 20)),
                              ),
                            ),
                          ),
                        ),
                      ),
                      ...List.generate(12, (index) => _buildKeyButton("F${index + 1}", 1.0 + ((index + 1) * 0.01))),
                      _buildKeyButton("ESC", 1.13, defaultColor: Colors.red[900]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}