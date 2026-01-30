import 'package:flutter/material.dart';
import 'package:flutter_app/core/bridge/js_bridge_client.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/qr_code/application/build_qr_payload_use_case.dart';
import 'first_time_experience_screen.dart';

/// Wired widget that connects FirstTimeExperienceScreen to business logic.
class FirstTimeExperienceWired extends StatefulWidget {
  final IdentityRepository repository;
  final JsBridge bridge;

  const FirstTimeExperienceWired({
    super.key,
    required this.repository,
    required this.bridge,
  });

  @override
  State<FirstTimeExperienceWired> createState() =>
      _FirstTimeExperienceWiredState();
}

class _FirstTimeExperienceWiredState extends State<FirstTimeExperienceWired> {
  String? _qrData;
  String _username = 'Username';
  IdentityModel? _identity;

  @override
  void initState() {
    super.initState();
    emitFlowEvent(
      layer: 'FL',
      event: 'FTE_FL_SCREEN_INIT',
      details: {},
    );
    _loadIdentityAndBuildQR();
  }

  Future<void> _loadIdentityAndBuildQR() async {
    try {
      final identity = await widget.repository.loadIdentity();
      if (identity == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'FTE_FL_NO_IDENTITY',
          details: {},
        );
        return;
      }

      _identity = identity;
      _username = identity.username;

      await _buildQRPayload();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FTE_FL_LOAD_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _buildQRPayload() async {
    try {
      Future<Map<String, dynamic>> jsSign(
          String dataToSign, String privateKey) {
        return callJsSignPayload(
          bridge: widget.bridge,
          dataToSign: dataToSign,
          privateKey: privateKey,
        );
      }

      final (result, qrString) = await buildQRPayload(
        repo: widget.repository,
        callJsSign: jsSign,
      );

      if (result == BuildQRPayloadResult.success && mounted) {
        setState(() {
          _qrData = qrString;
        });
        emitFlowEvent(
          layer: 'FL',
          event: 'FTE_FL_QR_GENERATED',
          details: {},
        );
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FTE_FL_QR_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _onUsernameChanged(String newUsername) async {
    if (_identity == null) return;

    final updatedIdentity = IdentityModel(
      peerId: _identity!.peerId,
      publicKey: _identity!.publicKey,
      privateKey: _identity!.privateKey,
      mnemonic12: _identity!.mnemonic12,
      username: newUsername,
      createdAt: _identity!.createdAt,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );

    try {
      await widget.repository.saveIdentity(updatedIdentity);
      _identity = updatedIdentity;

      setState(() {
        _username = newUsername;
        _qrData = null; // Clear QR while regenerating
      });

      emitFlowEvent(
        layer: 'FL',
        event: 'FTE_FL_USERNAME_UPDATED',
        details: {'username': newUsername},
      );

      await _buildQRPayload();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FTE_FL_USERNAME_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  void _onCameraPressed() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Photo upload coming soon!')),
    );
  }

  void _onScanPressed() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('QR scanner coming soon!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FirstTimeExperienceScreen(
        qrData: _qrData,
        username: _username,
        onCameraPressed: _onCameraPressed,
        onUsernameChanged: _onUsernameChanged,
        onScanPressed: _onScanPressed,
      ),
    );
  }
}
