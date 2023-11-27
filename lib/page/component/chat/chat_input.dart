import 'dart:async';
import 'dart:io';

import 'package:askaide/helper/ability.dart';
import 'package:askaide/helper/haptic_feedback.dart';
import 'package:askaide/helper/model_resolver.dart';
import 'package:askaide/helper/platform.dart';
import 'package:askaide/helper/upload.dart';
import 'package:askaide/lang/lang.dart';
import 'package:askaide/page/component/loading.dart';
import 'package:askaide/page/component/dialog.dart';
import 'package:askaide/page/component/theme/custom_size.dart';
import 'package:askaide/repo/settings_repo.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:askaide/page/component/theme/custom_theme.dart';
import 'package:record/record.dart';

class ChatInput extends StatefulWidget {
  final Function(String value) onSubmit;
  final ValueNotifier<bool> enableNotifier;
  final Widget? toolbar;
  final bool enableImageUpload;
  final Function()? onNewChat;
  final String hintText;
  final Function()? onVoiceRecordTappedEvent;
  final List<Widget> Function()? leftSideToolsBuilder;

  const ChatInput({
    super.key,
    required this.onSubmit,
    required this.enableNotifier,
    this.enableImageUpload = true,
    this.toolbar,
    this.onNewChat,
    this.hintText = '',
    this.onVoiceRecordTappedEvent,
    this.leftSideToolsBuilder,
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final TextEditingController _textController = TextEditingController();

  bool _isVoice = false;

  void toggleVoiceInput() {
    setState(() {
      _isVoice = !_isVoice;
    });
  }

  /// 用于监听键盘事件，实现回车发送消息，Shift+Enter换行
  late final FocusNode _focusNode = FocusNode(
    onKey: (node, event) {
      if (!event.isShiftPressed && event.logicalKey.keyLabel == 'Enter') {
        if (event is RawKeyDownEvent && widget.enableNotifier.value) {
          _handleSubmited(_textController.text.trim());
        }

        return KeyEventResult.handled;
      } else {
        return KeyEventResult.ignored;
      }
    },
  );

  final maxLength = 150000;

  @override
  void initState() {
    super.initState();

    _textController.addListener(() {
      setState(() {});
    });

    // 机器人回复完成后自动输入框自动获取焦点
    if (!PlatformTool.isAndroid() && !PlatformTool.isIOS()) {
      widget.enableNotifier.addListener(() {
        if (widget.enableNotifier.value) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  // input widget
  Widget _buildTextInput() {
    final customColors = Theme.of(context).extension<CustomColors>()!;

    return Expanded(
      child: Container(
        height: 50.0, // Set a fixed height
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          // 阴影
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              offset: const Offset(0, 0),
              blurRadius: 5,
              spreadRadius: 1,
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Expanded(
              child: TextFormField(
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                maxLines: 5,
                minLines: 1,
                maxLength: maxLength,
                focusNode: _focusNode,
                controller: _textController,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: const TextStyle(
                    fontSize: CustomSize.defaultHintTextSize,
                  ),
                  border: InputBorder.none,
                  counterText: '',
                ),
              ),
            ),
            // 聊天发送按钮
            _buildSendOrVoiceButton(context, customColors),
          ],
        ),
      ),
    );
  }

  var voiceRecording = false;
  final record = Record();
  DateTime? _voiceStartTime;
  Timer? timer;
  var millSeconds = 0;

  Widget _buildVoiceInput() {
    return Expanded(
      child: GestureDetector(
        // 上滑取消录音
        // onVerticalDragUpdate: (details) async {
        //   if (!voiceRecording) {
        //     return;
        //   }

        //   if (details.delta.dy < -50) {
        //     await onRecordStop();
        //   }
        // },
        onLongPressEnd: (details) async {
          if (!voiceRecording) {
            return;
          }

          setState(() {
            voiceRecording = false;
          });
          await onRecordStop();
        },
        onLongPressStart: (details) async {
          widget.onVoiceRecordTappedEvent?.call();
          record.hasPermission().then((hasPermission) {
            if (!hasPermission) {
              showErrorMessage('请授予录音权限');
            }
          });

          if (await record.hasPermission()) {
            // 震动反馈
            HapticFeedbackHelper.heavyImpact();

            setState(() {
              voiceRecording = true;
              _voiceStartTime = DateTime.now();
            });
            // Start recording
            await record.start(
              encoder: AudioEncoder.aacLc, // by default
              bitRate: 128000, // by default
              samplingRate: 44100, // by default
            );

            setState(() {
              millSeconds = 0;
            });
            if (timer != null) {
              timer!.cancel();
              timer = null;
            }

            timer = Timer.periodic(const Duration(milliseconds: 100),
                (timer) async {
              if (_voiceStartTime == null) {
                timer.cancel();
                return;
              }

              if (DateTime.now().difference(_voiceStartTime!).inSeconds >= 60) {
                await onRecordStop();
                return;
              }

              setState(() {
                millSeconds =
                    DateTime.now().difference(_voiceStartTime!).inMilliseconds;
              });
            });
          }
        },
        child: Container(
          height: 50.0, // Set a fixed height
          decoration: BoxDecoration(
            color: voiceRecording
                ? const Color.fromARGB(255, 33, 65, 243)
                : Colors.white,
            borderRadius: BorderRadius.circular(12),
            // 阴影
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                offset: const Offset(0, 0),
                blurRadius: 5,
                spreadRadius: 1,
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                  child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(), // Add this to push the text and icon to the center and right
                  voiceRecording
                      ? LoadingAnimationWidget.staggeredDotsWave(
                          color: Colors.white,
                          size: 30,
                        )
                      : const Text("按住说话"),
                  // 点击切换到文本输入
                  voiceRecording
                      ? const SizedBox()
                      : IconButton(
                          onPressed: toggleVoiceInput,
                          icon: const Icon(Icons.keyboard),
                        ),
                ],
              )),
            ],
          ),
        ),
      ),
    );
  }

  Future onRecordStop() async {
    timer?.cancel();

    var resPath = await record.stop();
    if (resPath == null) {
      showErrorMessage('语音输入失败');
      return;
    }

    final voiceDuration = DateTime.now().difference(_voiceStartTime!).inSeconds;
    if (voiceDuration < 2) {
      showErrorMessage('说话时间太短');
      _voiceStartTime = null;
      File.fromUri(Uri.parse(resPath)).delete();
      return;
    }

    if (voiceDuration > 60) {
      showErrorMessage('说话时间太长');
      _voiceStartTime = null;
      File.fromUri(Uri.parse(resPath)).delete();
      return;
    }

    _voiceStartTime = null;

    final cancel = BotToast.showCustomLoading(
      toastBuilder: (cancel) {
        return LoadingIndicator(
          message: AppLocale.processingWait.getString(context),
        );
      },
      allowClick: false,
      duration: const Duration(seconds: 120),
    );

    try {
      final audioFile = File.fromUri(Uri.parse(resPath));
      final text = await ModelResolver.instance.audioToText(audioFile);
      _textController.text = text;
      _handleSubmited(text);
    } catch (e) {
      // ignore: use_build_context_synchronously
      showErrorMessageEnhanced(context, e);
    } finally {
      cancel();
      // 删除临时文件
      if (!resPath.startsWith('blob:')) {
        File.fromUri(Uri.parse(resPath)).delete();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final customColors = Theme.of(context).extension<CustomColors>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: customColors.backgroundColor,
      ),
      child: Builder(builder: (context) {
        final setting = context.read<SettingRepository>();
        return Column(
          children: [
            // 工具栏
            if (widget.toolbar != null)
              Row(
                children: [
                  Expanded(child: widget.toolbar!),
                  Text(
                    "${_textController.text.length}/$maxLength",
                    textScaleFactor: 0.8,
                    style: TextStyle(
                      color: customColors.chatInputPanelText,
                    ),
                  ),
                ],
              ),
            // if (widget.toolbar != null)
            const SizedBox(height: 8),
            // 聊天内容输入栏
            SingleChildScrollView(
              child: Slidable(
                startActionPane: widget.onNewChat != null
                    ? ActionPane(
                        extentRatio: 0.3,
                        motion: const ScrollMotion(),
                        children: [
                          SlidableAction(
                            autoClose: true,
                            label: AppLocale.newChat.getString(context),
                            backgroundColor: Colors.blue,
                            borderRadius:
                                const BorderRadius.all(Radius.circular(20)),
                            onPressed: (_) {
                              widget.onNewChat!();
                            },
                          ),
                          const SizedBox(width: 10),
                        ],
                      )
                    : null,
                child: Row(
                  children: [
                    // 聊天功能按钮
                    Row(
                      children: [
                        if (!_isVoice)
                          _buildImageUploadButton(
                              context, setting, customColors),
                        if (widget.leftSideToolsBuilder != null)
                          ...widget.leftSideToolsBuilder!(),
                      ],
                    ),
                    // 聊天输入框
                    _isVoice ? _buildVoiceInput() : _buildTextInput(),
                  ],
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  /// 构建发送或者语音按钮
  Widget _buildSendOrVoiceButton(
    BuildContext context,
    CustomColors customColors,
  ) {
    if (!widget.enableNotifier.value) {
      return LoadingAnimationWidget.beat(
        color: customColors.linkColor!,
        size: 20,
      );
    }

    return _textController.text == ''
        ? InkWell(
            onTap: () {
              toggleVoiceInput();
            },
            child: Icon(
              Icons.mic,
              color: customColors.chatInputPanelText,
            ),
          )
        : IconButton(
            onPressed: () => _handleSubmited(_textController.text.trim()),
            icon: Icon(
              Icons.send,
              color: _textController.text.trim().isNotEmpty
                  ? const Color.fromRGBO(0, 102, 255, 1)
                  : null,
            ),
            splashRadius: 20,
            tooltip: AppLocale.send.getString(context),
            color: customColors.chatInputPanelText,
          );
  }

  /// 构建图片上传按钮
  Widget _buildImageUploadButton(
    BuildContext context,
    SettingRepository setting,
    CustomColors customColors,
  ) {
    return IconButton(
      onPressed: () async {
        HapticFeedbackHelper.mediumImpact();
        FilePickerResult? result =
            await FilePicker.platform.pickFiles(type: FileType.image);
        if (result != null && result.files.isNotEmpty) {
          var cancel = BotToast.showCustomLoading(
              toastBuilder: (void Function() cancelFunc) {
            return Container(
              padding: const EdgeInsets.all(15),
              decoration: const BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.all(Radius.circular(8))),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    AppLocale.uploading.getString(context),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  const CircularProgressIndicator(
                    backgroundColor: Colors.white,
                  ),
                ],
              ),
            );
          });
          if (PlatformTool.isWeb()) {
            final fileBytes = result.files.first.bytes;
            var upload = ImageUploader(setting).uploadData(fileBytes!);
            upload.then((value) {
              _handleSubmited(
                '![${value.name}](${value.url})',
                notSend: true,
              );
            }).onError((error, stackTrace) {
              showErrorMessageEnhanced(context, error!);
            }).whenComplete(() => cancel());
          } else {
            var upload =
                ImageUploader(setting).upload(result.files.single.path!);
            upload.then((value) {
              _handleSubmited(
                '![${value.name}](${value.url})',
                notSend: true,
              );
            }).onError((error, stackTrace) {
              showErrorMessageEnhanced(context, error!);
            }).whenComplete(() => cancel());
          }
        }
      },
      icon: const Icon(Icons.camera_alt),
      color: customColors.chatInputPanelText,
      splashRadius: 20,
      tooltip: AppLocale.uploadImage.getString(context),
    );
  }

  /// 处理输入框提交
  void _handleSubmited(String text, {bool notSend = false}) {
    if (notSend) {
      var cursorPos = _textController.selection.base.offset;
      if (cursorPos < 0) {
        _textController.text = text;
      } else {
        String suffixText = _textController.text.substring(cursorPos);
        String prefixText = _textController.text.substring(0, cursorPos);
        _textController.text = prefixText + text + suffixText;
        _textController.selection = TextSelection(
          baseOffset: cursorPos + text.length,
          extentOffset: cursorPos + text.length,
        );
      }

      _focusNode.requestFocus();

      return;
    }

    if (text != '') {
      widget.onSubmit(text);
      _textController.clear();
    }

    _focusNode.requestFocus();
  }
}
