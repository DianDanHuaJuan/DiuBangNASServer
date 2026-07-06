// 文件输入：ServerCubitImpl
// 文件职责：管理服务启停状态，接收页面动作并调用 UseCase
// 文件对外接口：ServerCubit, ServerCubitImpl
// 文件包含：ServerCubit, ServerCubitImpl
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/device/local_network_address_service.dart';
import '../../../../core/device/local_network_resolution.dart';
import '../../../../core/state/view_status.dart';
import '../../../../core/use_case/use_case.dart';
import '../../../../core/result/app_result.dart';
import '../../domain/repositories/server_repository.dart';
import '../cubit/server_state.dart';

abstract class ServerCubit {
  Future<void> startServer();
  Future<void> stopServer();
  Future<void> confirmIpAndStartServer(String ip);
  void cancelIpSelection();
}

class ServerCubitImpl extends Cubit<ServerState> implements ServerCubit {
  ServerCubitImpl({
    required UseCase<void, NoParams> startServerUseCase,
    required UseCase<void, NoParams> stopServerUseCase,
    required ServerRepository repository,
    required LocalNetworkAddressService localNetworkAddressService,
  }) : _startServerUseCase = startServerUseCase,
       _stopServerUseCase = stopServerUseCase,
       _repository = repository,
       _localNetworkAddressService = localNetworkAddressService,
       super(const ServerState());

  final UseCase<void, NoParams> _startServerUseCase;
  final UseCase<void, NoParams> _stopServerUseCase;
  final ServerRepository _repository;
  final LocalNetworkAddressService _localNetworkAddressService;
  Timer? _uptimeTimer;

  @override
  Future<void> startServer() async {
    if (state.serverStatus == ServerStatus.running ||
        state.serverStatus == ServerStatus.starting ||
        state.serverStatus == ServerStatus.awaitingIpSelection) {
      return;
    }

    emit(
      state.copyWith(
        viewStatus: ViewStatus.loading,
        serverStatus: ServerStatus.starting,
        clearPendingIpCandidates: true,
      ),
    );

    final resolution = await _localNetworkAddressService.resolveForServerStart();
    switch (resolution) {
      case LocalNetworkUnavailable():
        emit(
          state.copyWith(
            viewStatus: ViewStatus.failure,
            serverStatus: ServerStatus.error,
            errorMessage: '未检测到可用的网络接口，请检查网络连接后重试。',
          ),
        );
        return;
      case LocalNetworkNeedsSelection(:final candidates):
        emit(
          state.copyWith(
            viewStatus: ViewStatus.initial,
            serverStatus: ServerStatus.awaitingIpSelection,
            pendingIpCandidates: candidates,
          ),
        );
        return;
      case LocalNetworkResolved(:final ip):
        await _startServerWithResolvedIp(ip);
    }
  }

  @override
  Future<void> confirmIpAndStartServer(String ip) async {
    if (state.serverStatus != ServerStatus.awaitingIpSelection) {
      return;
    }

    emit(
      state.copyWith(
        viewStatus: ViewStatus.loading,
        serverStatus: ServerStatus.starting,
        clearPendingIpCandidates: true,
      ),
    );

    await _localNetworkAddressService.setSelectedIp(ip);
    await _startServerWithResolvedIp(ip);
  }

  @override
  void cancelIpSelection() {
    if (state.serverStatus != ServerStatus.awaitingIpSelection) {
      return;
    }

    emit(
      state.copyWith(
        viewStatus: ViewStatus.initial,
        serverStatus: ServerStatus.stopped,
        clearPendingIpCandidates: true,
      ),
    );
  }

  Future<void> _startServerWithResolvedIp(String ip) async {
    final result = await _startServerUseCase(const NoParams());

    switch (result) {
      case AppSuccess():
        emit(
          state.copyWith(
            viewStatus: ViewStatus.success,
            serverStatus: ServerStatus.running,
            ipAddress: _repository.ipAddress ?? ip,
            port: _repository.port ?? state.port,
            serverStartTime: DateTime.now(),
          ),
        );
        _startUptimeTimer();
      case AppError():
        emit(
          state.copyWith(
            viewStatus: ViewStatus.failure,
            serverStatus: ServerStatus.error,
            errorMessage: result.failure.message,
          ),
        );
    }
  }

  @override
  Future<void> stopServer() async {
    if (state.serverStatus == ServerStatus.stopped ||
        state.serverStatus == ServerStatus.stopping) {
      return;
    }

    emit(
      state.copyWith(
        viewStatus: ViewStatus.loading,
        serverStatus: ServerStatus.stopping,
        clearPendingIpCandidates: true,
      ),
    );

    final result = await _stopServerUseCase(const NoParams());

    switch (result) {
      case AppSuccess():
        _stopUptimeTimer();
        emit(
          state.copyWith(
            viewStatus: ViewStatus.success,
            serverStatus: ServerStatus.stopped,
            clearServerStartTime: true,
          ),
        );
      case AppError():
        emit(
          state.copyWith(
            viewStatus: ViewStatus.failure,
            serverStatus: ServerStatus.error,
            errorMessage: result.failure.message,
          ),
        );
    }
  }

  void _startUptimeTimer() {
    _uptimeTimer?.cancel();
    _uptimeTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      emit(state.copyWith(tick: state.tick + 1));
    });
  }

  void _stopUptimeTimer() {
    _uptimeTimer?.cancel();
    _uptimeTimer = null;
  }

  @override
  Future<void> close() {
    _stopUptimeTimer();
    return super.close();
  }
}
