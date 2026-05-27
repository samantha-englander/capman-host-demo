import 'package:capman_host/di/env.dart';
import 'package:capman_host/shared_data/networking/cloud_sync/cloud_sync_mdp.dart';
import 'package:capman_host/shared_data/networking/interceptor/device_auth_interceptor.dart';
import 'package:cloud_sync_dart/generated/cloud_sync_service.pbgrpc.dart';
import 'package:grpc/grpc.dart';
import 'package:injectable/injectable.dart';

const CloudSyncHost = Named('CloudSyncHost');

@module
abstract class GrpcModule {
  @lazySingleton
  @development
  @demo
  @CloudSyncHost
  String provideDevCloudSyncHost() => 'ws-api.toasttab.com'; //unused

  @lazySingleton
  @staging
  @testEnvironment
  @CloudSyncHost
  String provideStagingCloudSyncHost() => 'ws-preprod-sync.eng.toasttab.com';

  @lazySingleton
  @production
  @CloudSyncHost
  String provideProdCloudSyncHost() => 'ws-sync.toasttab.com';

  @lazySingleton
  CloudSyncServiceClient provideCloudSyncServiceClient(
    @CloudSyncHost String host,
    CloudSyncMdp provider,
    DeviceAuthInterceptor deviceAuth,
  ) => CloudSyncServiceClient(
    ClientChannel(
      host,
      options: const ChannelOptions(
        userAgent: 'toast-booking-host-app',
        connectTimeout: Duration(seconds: 10),
      ),
    ),
    options: CallOptions(
      providers: [provider.updateMetadata, deviceAuth.updateMetadata],
    ),
  );
}
