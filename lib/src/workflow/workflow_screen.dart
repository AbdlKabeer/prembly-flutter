import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../contract/errors.dart';
import '../contract/workflow_types.dart';
import 'hosted_flow.dart';

/// Where the wrapper page claims to live: the hosted app's own origin.
///
/// This is deliberate. On iOS a frame whose origin differs from the page that holds it did not run
/// its scripts in testing (the hosted app's events never arrived), while a same-origin frame does.
/// Sharing the origin is safe here: the page only accepts messages whose origin is the hosted app's
/// and that carry this flow's nonce, and a page the frame navigates to is cross-origin, so it can
/// neither read the nonce nor pass the origin check. It also suits hosted apps that only allow
/// framing by their own origin.
@visibleForTesting
String wrapperBaseUrlFor(Uri link) => '${link.origin}/';

/// Name of the JavaScript channel the wrapper page posts to.
const String bridgeChannel = 'PremblyBridge';

Uri parseHostedLink(String link) {
  final Uri url;
  try {
    url = Uri.parse(link);
  } catch (_) {
    throw PremblyError(ErrorCode.invalidRequest,
        'Prembly: the hosted link is not a valid URL.');
  }
  if ((url.scheme != 'https' && url.scheme != 'http') || url.host.isEmpty) {
    throw PremblyError(
        ErrorCode.invalidRequest, 'Prembly: the hosted link must be http(s).');
  }
  return url;
}

/// The page the WebView loads. It shows the hosted app in an iframe, as the web launcher does,
/// because the hosted app only posts its events when it runs inside a frame. Messages are forwarded
/// to Flutter only when they come from that iframe and from the link's origin.
@visibleForTesting
String buildWrapperHtml({required Uri link, required String nonce}) {
  final origin = link.origin;
  const attribute = HtmlEscape(HtmlEscapeMode.attribute);
  // JSON strings are valid JavaScript string literals; "<" is escaped so a value can never close
  // the script element.
  String js(String value) => jsonEncode(value).replaceAll('<', r'<');
  return '''<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<style>html,body{margin:0;height:100%;background:#fff}iframe{display:block;border:0;width:100%;height:100%;background:#fff}</style>
</head>
<body>
<iframe id="flow" src="${attribute.convert(link.toString())}" allow="camera; microphone; clipboard-read; clipboard-write" title="Prembly verification"></iframe>
<script>
(function () {
  var frame = document.getElementById('flow');
  var origin = ${js(origin)};
  var nonce = ${js(nonce)};
  window.addEventListener('message', function (event) {
    if (event.origin !== origin) return;
    if (!frame.contentWindow || event.source !== frame.contentWindow) return;
    try {
      $bridgeChannel.postMessage(JSON.stringify({ n: nonce, d: event.data }));
    } catch (e) {}
  });
})();
</script>
</body>
</html>''';
}

/// The default launcher: a full-screen route with the hosted app in a WebView.
WorkflowHandle launchWorkflowScreen(LaunchOptions options) {
  final link = parseHostedLink(options.link);
  final navigator = Navigator.of(options.context, rootNavigator: true);

  late final MaterialPageRoute<void> route;
  late final HostedFlow flow;
  flow = HostedFlow(
    product: options.product,
    sessionId: options.sessionId,
    onEvent: options.onEvent,
    callback: options.callback,
    onClose: () {
      if (route.isActive) navigator.removeRoute(route);
    },
  );
  route = MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => WorkflowScreen(flow: flow, link: link),
  );
  navigator.push(route);
  return flow;
}

class WorkflowScreen extends StatefulWidget {
  const WorkflowScreen({super.key, required this.flow, required this.link});

  final HostedFlow flow;
  final Uri link;

  @override
  State<WorkflowScreen> createState() => _WorkflowScreenState();
}

class _WorkflowScreenState extends State<WorkflowScreen> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();

    final PlatformWebViewControllerCreationParams params =
        defaultTargetPlatform == TargetPlatform.iOS
            ? WebKitWebViewControllerCreationParams(
                allowsInlineMediaPlayback: true,
                mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
              )
            : const PlatformWebViewControllerCreationParams();

    _controller = WebViewController.fromPlatformCreationParams(
      params,
      onPermissionRequest: _onPermissionRequest,
    )
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..addJavaScriptChannel(
        bridgeChannel,
        onMessageReceived: (message) =>
            widget.flow.handleBridgeMessage(message.message),
      )
      ..loadHtmlString(
        buildWrapperHtml(link: widget.link, nonce: widget.flow.nonce),
        baseUrl: wrapperBaseUrlFor(widget.link),
      );

    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(kDebugMode);
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
  }

  /// The hosted app asks for the camera (and the microphone) from inside the frame. On Android the
  /// app must also hold the runtime permission; iOS asks by itself the first time.
  Future<void> _onPermissionRequest(WebViewPermissionRequest request) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final needed = <Permission>[
        if (request.types.contains(WebViewPermissionResourceType.camera))
          Permission.camera,
        if (request.types.contains(WebViewPermissionResourceType.microphone))
          Permission.microphone,
      ];
      for (final permission in needed) {
        final status = await permission.request();
        if (!status.isGranted) {
          await request.deny();
          return;
        }
      }
    }
    await request.grant();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // The back gesture means the person is closing the flow: report it as cancelled.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.flow.close();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(child: WebViewWidget(controller: _controller)),
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: Colors.white.withValues(alpha: 0.95),
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close, color: Color(0xFF111111)),
                    onPressed: widget.flow.close,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
